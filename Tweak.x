// TikTok个人中心网络请求抓包插件
// 作者: 海鸥
// 功能: 拦截个人中心API请求，通过HTTP服务器查看，带悬浮窗

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <ifaddrs.h>

#define HLog(fmt, ...) NSLog(@"[TikTokCapture] " fmt, ##__VA_ARGS__)

// HTTP服务器端口
#define HTTP_PORT 9999

// 全局变量
static UIButton *floatingButton = nil;
static UIView *controlPanel = nil;
static NSMutableArray *capturedRequests = nil;
static int captureCount = 0;
static CFSocketRef serverSocket = NULL;

// 获取keyWindow（兼容iOS 13+）
static UIWindow *getKeyWindow() {
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        keyWindow = window;
                        break;
                    }
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

// 获取设备IP地址
static NSString* getDeviceIP() {
    NSString *address = @"获取中...";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = getifaddrs(&interfaces);
    if (success == 0) {
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            if(temp_addr->ifa_addr->sa_family == AF_INET) {
                if([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    return address;
}

// 显示控制面板
static void showControlPanel() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (controlPanel) {
            controlPanel.hidden = NO;
            return;
        }

        UIWindow *topWindow = objc_getAssociatedObject(floatingButton, "topWindow");
        if (!topWindow) return;

        // 半透明背景
        controlPanel = [[UIView alloc] initWithFrame:topWindow.bounds];
        controlPanel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];

        // 主面板
        CGFloat panelWidth = 300;
        CGFloat panelHeight = 280;
        UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((topWindow.bounds.size.width - panelWidth)/2,
                                                                   (topWindow.bounds.size.height - panelHeight)/2,
                                                                   panelWidth, panelHeight)];
        panel.backgroundColor = [[UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:0.95] colorWithAlphaComponent:1.0];
        panel.layer.cornerRadius = 15;
        panel.layer.masksToBounds = YES;

        // 标题
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, panelWidth, 30)];
        titleLabel.text = @"🎣 TikTok抓包";
        titleLabel.textColor = [UIColor whiteColor];
        titleLabel.font = [UIFont boldSystemFontOfSize:20];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        [panel addSubview:titleLabel];

        // 抓包数量
        UILabel *countLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 65, panelWidth-40, 25)];
        countLabel.text = [NSString stringWithFormat:@"已捕获: %d 条请求", captureCount];
        countLabel.textColor = [UIColor colorWithRed:0.6 green:0.9 blue:0.6 alpha:1.0];
        countLabel.font = [UIFont systemFontOfSize:16];
        countLabel.textAlignment = NSTextAlignmentCenter;
        [panel addSubview:countLabel];

        // HTTP地址
        NSString *deviceIP = getDeviceIP();
        UILabel *urlLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 95, panelWidth-40, 40)];
        urlLabel.text = [NSString stringWithFormat:@"http://%@:%d", deviceIP, HTTP_PORT];
        urlLabel.textColor = [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1.0];
        urlLabel.font = [UIFont systemFontOfSize:14];
        urlLabel.textAlignment = NSTextAlignmentCenter;
        urlLabel.numberOfLines = 2;
        [panel addSubview:urlLabel];

        // 浏览器查看按钮
        UIButton *browserBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        browserBtn.frame = CGRectMake(30, 145, panelWidth-60, 45);
        [browserBtn setTitle:@"📱 Safari查看数据" forState:UIControlStateNormal];
        [browserBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        browserBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        browserBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];
        browserBtn.layer.cornerRadius = 10;
        [browserBtn addTarget:browserBtn action:@selector(openBrowser:) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:browserBtn];

        // 关闭按钮
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(30, 205, panelWidth-60, 45);
        [closeBtn setTitle:@"关闭" forState:UIControlStateNormal];
        [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        closeBtn.titleLabel.font = [UIFont systemFontOfSize:15];
        closeBtn.backgroundColor = [UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:1.0];
        closeBtn.layer.cornerRadius = 10;
        [closeBtn addTarget:closeBtn action:@selector(hidePanel:) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:closeBtn];

        [controlPanel addSubview:panel];
        [topWindow addSubview:controlPanel];

        // 存储引用
        objc_setAssociatedObject(floatingButton, "controlPanel", controlPanel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

// 隐藏控制面板
static void hideControlPanel() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (controlPanel) {
            controlPanel.hidden = YES;
        }
    });
}

// 悬浮窗
static void createFloatingButton() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (floatingButton) return;

        UIWindow *keyWindow = getKeyWindow();
        if (!keyWindow) return;

        floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        floatingButton.frame = CGRectMake(20, 100, 80, 80);
        floatingButton.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.8];
        floatingButton.layer.cornerRadius = 40;
        floatingButton.layer.masksToBounds = YES;
        [floatingButton setTitle:@"运行中\n0" forState:UIControlStateNormal];
        floatingButton.titleLabel.numberOfLines = 2;
        floatingButton.titleLabel.textAlignment = NSTextAlignmentCenter;
        floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];

        // 确保在最顶层显示
        UIWindow *topWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        topWindow.windowLevel = UIWindowLevelAlert + 1;
        topWindow.backgroundColor = [UIColor clearColor];
        topWindow.hidden = NO;
        topWindow.userInteractionEnabled = YES;
        [topWindow addSubview:floatingButton];

        // 存储window引用防止释放
        objc_setAssociatedObject(floatingButton, "topWindow", topWindow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        // 添加长按拖动手势
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:floatingButton action:@selector(handleLongPress:)];
        longPress.minimumPressDuration = 0.3;
        [floatingButton addGestureRecognizer:longPress];

        // 添加点击手势（用手势识别器，不用addTarget避免冲突）
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:floatingButton action:@selector(onButtonTap:)];
        [floatingButton addGestureRecognizer:tap];

        floatingButton.userInteractionEnabled = YES;

        HLog(@"悬浮窗已创建");
    });
}

// 更新悬浮窗计数
static void updateFloatingButton() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (floatingButton) {
            [floatingButton setTitle:[NSString stringWithFormat:@"运行中\n%d", captureCount] forState:UIControlStateNormal];
        }
    });
}

// HTTP响应生成
static NSString* generateHTMLResponse() {
    NSMutableString *html = [NSMutableString string];
    [html appendString:@"<!DOCTYPE html><html><head><meta charset='UTF-8'><title>TikTok抓包数据</title>"];
    [html appendString:@"<style>body{font-family:monospace;padding:20px;background:#1e1e1e;color:#d4d4d4;}"];
    [html appendString:@".request{background:#2d2d2d;margin:10px 0;padding:15px;border-radius:5px;border-left:4px solid #007acc;}"];
    [html appendString:@"h1{color:#4ec9b0;}h2{color:#dcdcaa;margin-top:10px;}"];
    [html appendString:@".url{color:#ce9178;word-break:break-all;}.json{background:#1e1e1e;padding:10px;border-radius:3px;overflow-x:auto;white-space:pre-wrap;word-wrap:break-word;}"];
    [html appendString:@".header{color:#9cdcfe;}</style></head><body>"];
    [html appendFormat:@"<h1>🎣 TikTok抓包数据 (共%d条)</h1>", captureCount];

    @synchronized(capturedRequests) {
        for (NSDictionary *req in [capturedRequests reverseObjectEnumerator]) {
            [html appendString:@"<div class='request'>"];
            [html appendFormat:@"<h2>📡 %@</h2>", req[@"time"]];
            [html appendFormat:@"<p class='url'><strong>URL:</strong> %@</p>", req[@"url"]];
            [html appendFormat:@"<p><strong>方法:</strong> %@</p>", req[@"method"]];

            if (req[@"headers"]) {
                [html appendString:@"<h2>📋 请求头</h2><div class='json'>"];
                NSDictionary *headers = req[@"headers"];
                for (NSString *key in headers) {
                    [html appendFormat:@"<span class='header'>%@:</span> %@<br>", key, headers[key]];
                }
                [html appendString:@"</div>"];
            }

            if (req[@"requestBody"]) {
                [html appendString:@"<h2>📤 请求体</h2>"];
                [html appendFormat:@"<div class='json'>%@</div>", req[@"requestBody"]];
            }

            if (req[@"responseHeaders"]) {
                [html appendString:@"<h2>📥 响应头</h2><div class='json'>"];
                NSDictionary *respHeaders = req[@"responseHeaders"];
                for (NSString *key in respHeaders) {
                    [html appendFormat:@"<span class='header'>%@:</span> %@<br>", key, respHeaders[key]];
                }
                [html appendString:@"</div>"];
            }

            if (req[@"response"]) {
                [html appendString:@"<h2>✅ 响应体</h2>"];
                [html appendFormat:@"<div class='json'>%@</div>", req[@"response"]];
            }

            [html appendString:@"</div>"];
        }
    }

    [html appendString:@"</body></html>"];
    return html;
}

// HTTP服务器回调
static void handleConnection(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    if (type != kCFSocketAcceptCallBack) return;

    CFSocketNativeHandle nativeSocket = *(CFSocketNativeHandle *)data;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        char buffer[1024];
        ssize_t bytesRead = recv(nativeSocket, buffer, sizeof(buffer)-1, 0);

        if (bytesRead > 0) {
            NSString *html = generateHTMLResponse();
            NSData *htmlData = [html dataUsingEncoding:NSUTF8StringEncoding];

            NSString *response = [NSString stringWithFormat:
                @"HTTP/1.1 200 OK\r\n"
                @"Content-Type: text/html; charset=UTF-8\r\n"
                @"Content-Length: %lu\r\n"
                @"Connection: close\r\n\r\n", (unsigned long)htmlData.length];

            send(nativeSocket, [response UTF8String], [response length], 0);
            send(nativeSocket, [htmlData bytes], [htmlData length], 0);
        }

        close(nativeSocket);
    });
}

// 启动HTTP服务器
static void startHTTPServer() {
    CFSocketContext context = {0, NULL, NULL, NULL, NULL};
    serverSocket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP,
                                   kCFSocketAcceptCallBack, handleConnection, &context);

    if (!serverSocket) {
        HLog(@"❌ 创建Socket失败");
        return;
    }

    int yes = 1;
    setsockopt(CFSocketGetNative(serverSocket), SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(HTTP_PORT);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    CFDataRef addressData = CFDataCreate(NULL, (const UInt8 *)&addr, sizeof(addr));

    if (CFSocketSetAddress(serverSocket, addressData) != kCFSocketSuccess) {
        HLog(@"❌ 绑定端口%d失败", HTTP_PORT);
        CFRelease(serverSocket);
        serverSocket = NULL;
        CFRelease(addressData);
        return;
    }

    CFRelease(addressData);

    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, serverSocket, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CFRelease(source);

    HLog(@"✅ HTTP服务器已启动: http://localhost:%d", HTTP_PORT);
}

// 初始化
%ctor {
    capturedRequests = [[NSMutableArray alloc] init];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        createFloatingButton();
        startHTTPServer();
        HLog(@"========================================");
        HLog(@"✅ TikTok抓包插件已加载");
        HLog(@"📱 悬浮窗已显示");
        HLog(@"🌐 HTTP服务器: http://设备IP:%d", HTTP_PORT);
        HLog(@"========================================");
    });
}

// ============================================
// Hook NSURLSession - 拦截网络请求
// ============================================
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {

    NSString *urlString = request.URL.absoluteString;

    // 只拦截TikTok/抖音的API请求（放宽过滤条件，确保不遗漏）
    if ([urlString containsString:@"tiktok"] ||
        [urlString containsString:@"aweme"] ||
        [urlString containsString:@"musically"] ||
        [urlString containsString:@"api"] ||
        [urlString containsString:@"byteoversea"]) {

        HLog(@"🎯 拦截到请求: %@", urlString);

        // 记录请求时间
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        NSString *timeStr = [formatter stringFromDate:[NSDate date]];

        // 收集请求头（所有请求头，包括设备指纹）
        NSMutableDictionary *headers = [NSMutableDictionary dictionary];
        [request.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
            headers[key] = value;
        }];

        // 收集请求体（如果是POST/PUT等）
        NSString *requestBody = nil;
        if (request.HTTPBody) {
            requestBody = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
        }

        // Hook completionHandler
        void (^newHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            if (data && response) {
                // 先尝试解析JSON格式化，如果失败就用Base64保存原始数据
                NSString *responseBody = nil;
                NSError *jsonError = nil;
                id jsonObj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

                if (jsonObj && !jsonError) {
                    // JSON数据，格式化输出
                    NSData *prettyData = [NSJSONSerialization dataWithJSONObject:jsonObj options:NSJSONWritingPrettyPrinted error:nil];
                    responseBody = [[NSString alloc] initWithData:prettyData encoding:NSUTF8StringEncoding];
                } else {
                    // 非JSON或乱码，用Base64编码保存原始数据
                    responseBody = [NSString stringWithFormat:@"[Base64] %@", [data base64EncodedStringWithOptions:0]];
                }

                // 收集响应头（重要！包括服务器返回的所有头）
                NSMutableDictionary *responseHeaders = [NSMutableDictionary dictionary];
                if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                    [httpResponse.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
                        responseHeaders[key] = value;
                    }];
                }

                // 保存到数组（完整数据）
                @synchronized(capturedRequests) {
                    NSMutableDictionary *capturedData = [@{
                        @"time": timeStr,
                        @"url": urlString,
                        @"method": request.HTTPMethod ?: @"GET",
                        @"headers": headers,
                        @"response": responseBody ?: @"(空响应)",
                        @"responseHeaders": responseHeaders
                    } mutableCopy];

                    // 如果有请求体，添加进去
                    if (requestBody) {
                        capturedData[@"requestBody"] = requestBody;
                    }

                    [capturedRequests addObject:capturedData];

                    // 只保留最近100条
                    if (capturedRequests.count > 100) {
                        [capturedRequests removeObjectAtIndex:0];
                    }

                    captureCount++;
                    updateFloatingButton();

                    HLog(@"✅ 已捕获第%d条请求", captureCount);
                }
            }

            // 调用原始回调
            if (completionHandler) {
                completionHandler(data, response, error);
            }
        };

        return %orig(request, newHandler);
    }

    return %orig;
}

%end

// ============================================
// UIButton拖动手势处理和点击事件
// ============================================
@interface UIButton (DragSupport)
- (void)handleLongPress:(UILongPressGestureRecognizer *)recognizer;
- (void)onButtonTap:(UITapGestureRecognizer *)recognizer;
- (void)openBrowser:(UIButton *)sender;
- (void)hidePanel:(UIButton *)sender;
@end

@implementation UIButton (DragSupport)
- (void)handleLongPress:(UILongPressGestureRecognizer *)recognizer {
    UIView *view = recognizer.view;
    CGPoint location = [recognizer locationInView:view.superview];

    if (recognizer.state == UIGestureRecognizerStateBegan || recognizer.state == UIGestureRecognizerStateChanged) {
        view.center = location;
    }
}

- (void)onButtonTap:(UITapGestureRecognizer *)recognizer {
    showControlPanel();
}

- (void)openBrowser:(UIButton *)sender {
    NSString *deviceIP = getDeviceIP();
    NSString *urlString = [NSString stringWithFormat:@"http://%@:%d", deviceIP, HTTP_PORT];
    NSURL *url = [NSURL URLWithString:urlString];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    hideControlPanel();
}

- (void)hidePanel:(UIButton *)sender {
    hideControlPanel();
}
@end
