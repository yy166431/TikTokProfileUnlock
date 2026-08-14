#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

#define HTTP_PORT 9999

static NSMutableArray *capturedData = nil;
static CFSocketRef serverSocket = NULL;
static int captureCount = 0;
static UIButton *floatingButton = nil;
static UIWindow *dataWindow = nil;

// URL 缓存：用于关联请求和响应
// Key: 线程ID, Value: @{url, headers, timestamp}
static NSMutableDictionary *pendingRequests = nil;

// 接口声明
@interface TTHttpTask : NSObject
- (NSURLRequest *)request;
- (void)resume;
- (void)readDataOfMinLength:(NSUInteger)minBytes maxLength:(NSUInteger)maxBytes timeout:(NSTimeInterval)timeout completionHandler:(void (^)(NSData *data, BOOL atEOF, NSError *error))completionHandler;
@end

@interface TTHttpResponseChromium : NSObject
- (NSURL *)URL;
- (NSDictionary *)allHeaderFields;
@end

// 前置声明
static void showDataWindow();
static void closeDataWindow();

// ==================== 简易 HTTP 服务器 ====================

static NSString* generateHTML() {
    NSMutableString *html = [NSMutableString new];
    [html appendString:@"<html><head><meta charset='utf-8'><title>TikTok Capture</title>"];
    [html appendString:@"<style>body{font-family:monospace;padding:20px;background:#1a1a1a;color:#0f0}"];
    [html appendString:@".item{border:1px solid #0f0;margin:10px 0;padding:10px;background:#000}"];
    [html appendString:@".url{color:#0ff;word-break:break-all}"];
    [html appendString:@".json{color:#ff0;white-space:pre-wrap;max-height:300px;overflow:auto}"];
    [html appendString:@".label{color:#f90;font-weight:bold}"];
    [html appendString:@"</style></head><body>"];
    [html appendFormat:@"<h1>TikTok Profile Capture</h1><p>捕获数量: %d</p>", (int)capturedData.count];
    [html appendString:@"<div id='list'>"];

    for (NSDictionary *item in [capturedData reverseObjectEnumerator]) {
        [html appendString:@"<div class='item'>"];
        [html appendFormat:@"<span class='label'>ID:</span> %@<br>", item[@"id"]];
        [html appendFormat:@"<span class='label'>Type:</span> %@<br>", item[@"type"] ?: @"N/A"];

        if (item[@"url"]) {
            [html appendFormat:@"<span class='label'>URL:</span> <span class='url'>%@</span><br>", item[@"url"]];
        }
        if (item[@"method"]) {
            [html appendFormat:@"<span class='label'>Method:</span> %@<br>", item[@"method"]];
        }
        if (item[@"request_headers"]) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:item[@"request_headers"] options:NSJSONWritingPrettyPrinted error:nil];
            if (jsonData) {
                NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                [html appendFormat:@"<span class='label'>Request Headers:</span><pre class='json'>%@</pre>", jsonStr];
            }
        }
        if (item[@"response_headers"]) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:item[@"response_headers"] options:NSJSONWritingPrettyPrinted error:nil];
            if (jsonData) {
                NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                [html appendFormat:@"<span class='label'>Response Headers:</span><pre class='json'>%@</pre>", jsonStr];
            }
        }
        if (item[@"response_body"]) {
            NSString *resp = item[@"response_body"];
            if ([resp length] > 2000) {
                [html appendFormat:@"<span class='label'>Response Body:</span><pre class='json'>%@...</pre>", [resp substringToIndex:2000]];
            } else {
                [html appendFormat:@"<span class='label'>Response Body:</span><pre class='json'>%@</pre>", resp];
            }
        }
        if (item[@"response"]) {
            NSString *resp = item[@"response"];
            if ([resp length] > 2000) {
                [html appendFormat:@"<span class='label'>Response JSON:</span><pre class='json'>%@...</pre>", [resp substringToIndex:2000]];
            } else {
                [html appendFormat:@"<span class='label'>Response JSON:</span><pre class='json'>%@</pre>", resp];
            }
        }
        [html appendString:@"</div>"];
    }

    if (capturedData.count == 0) {
        [html appendString:@"<p>暂无数据，请刷新个人主页</p>"];
    }

    [html appendString:@"</div><script>setTimeout(()=>location.reload(),3000)</script></body></html>"];
    return html;
}

static void handleConnection(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    if (type != kCFSocketAcceptCallBack) return;

    CFSocketNativeHandle clientSocket = *(CFSocketNativeHandle *)data;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        char buffer[1024];
        recv(clientSocket, buffer, sizeof(buffer), 0);

        NSString *html = generateHTML();
        NSData *htmlData = [html dataUsingEncoding:NSUTF8StringEncoding];

        NSString *response = [NSString stringWithFormat:
            @"HTTP/1.1 200 OK\r\n"
            @"Content-Type: text/html; charset=utf-8\r\n"
            @"Content-Length: %lu\r\n"
            @"Connection: close\r\n\r\n",
            (unsigned long)htmlData.length];

        send(clientSocket, [response UTF8String], [response length], 0);
        send(clientSocket, [htmlData bytes], [htmlData length], 0);
        close(clientSocket);
    });
}

static void setupLocalServer() {
    if (serverSocket) return;

    capturedData = [NSMutableArray new];

    CFSocketContext context = {0, NULL, NULL, NULL, NULL};
    serverSocket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP,
        kCFSocketAcceptCallBack, handleConnection, &context);

    if (!serverSocket) {
        NSLog(@"[TKCapture] ✗ Failed to create socket");
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
        CFRelease(serverSocket);
        CFRelease(addressData);
        serverSocket = NULL;
        NSLog(@"[TKCapture] ✗ Failed to bind to port %d", HTTP_PORT);
        return;
    }

    CFRelease(addressData);

    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, serverSocket, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CFRelease(source);

    NSLog(@"[TKCapture] ✓ Server running on http://localhost:%d", HTTP_PORT);
}

// ==================== 悬浮窗 ====================

@interface UIButton (TKCapture)
- (void)onButtonTap;
- (void)handlePan:(UIPanGestureRecognizer *)gesture;
@end

@implementation UIButton (TKCapture)

- (void)onButtonTap {
    showDataWindow();
}

- (void)tkc_closeWindow {
    closeDataWindow();
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *button = gesture.view;
    CGPoint translation = [gesture translationInView:button.superview];

    button.center = CGPointMake(button.center.x + translation.x, button.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:button.superview];

    if (gesture.state == UIGestureRecognizerStateEnded) {
        // 自动吸边
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        CGFloat newX = button.center.x < screenWidth / 2 ? 30 : screenWidth - 30;

        [UIView animateWithDuration:0.3 animations:^{
            button.center = CGPointMake(newX, button.center.y);
        }];
    }
}

@end

static void createFloatingButton() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (floatingButton) return;

        // 获取 keyWindow
        UIWindow *keyWindow = nil;
        for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        if (!keyWindow) keyWindow = [[[UIApplication sharedApplication] windows] firstObject];
        if (!keyWindow) return;

        // 创建悬浮按钮
        floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        floatingButton.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 70, 100, 60, 60);
        floatingButton.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.8];
        floatingButton.layer.cornerRadius = 30;
        floatingButton.layer.masksToBounds = YES;
        [floatingButton setTitle:[NSString stringWithFormat:@"%d", (int)capturedData.count] forState:UIControlStateNormal];
        floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
        [floatingButton addTarget:floatingButton action:@selector(onButtonTap) forControlEvents:UIControlEventTouchUpInside];

        // 添加拖动手势
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:floatingButton action:@selector(handlePan:)];
        [floatingButton addGestureRecognizer:pan];

        [keyWindow addSubview:floatingButton];

        // 定时更新数字
        [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [floatingButton setTitle:[NSString stringWithFormat:@"%d", (int)capturedData.count] forState:UIControlStateNormal];
            });
        }];

        NSLog(@"[TKCapture] ✓ Floating button created");
    });
}

static void showDataWindow() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (dataWindow) {
            [dataWindow removeFromSuperview];
            dataWindow = nil;
            return;
        }

        // 创建数据显示窗口
        CGRect frame = [UIScreen mainScreen].bounds;
        dataWindow = [[UIWindow alloc] initWithFrame:frame];
        dataWindow.windowLevel = UIWindowLevelAlert + 1;
        dataWindow.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.95];

        // 创建文本视图
        UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(10, 50, frame.size.width - 20, frame.size.height - 100)];
        textView.backgroundColor = [UIColor clearColor];
        textView.textColor = [UIColor greenColor];
        textView.font = [UIFont systemFontOfSize:12];
        textView.editable = NO;

        // 生成显示内容
        NSMutableString *content = [NSMutableString new];
        [content appendFormat:@"TikTok Profile Capture\n捕获数量: %d\n\n", (int)capturedData.count];

        for (NSDictionary *item in [capturedData reverseObjectEnumerator]) {
            [content appendFormat:@"=== ID: %@ ===\n", item[@"id"]];
            [content appendFormat:@"类型: %@\n", item[@"type"]];

            if (item[@"url"]) {
                [content appendFormat:@"URL: %@\n", item[@"url"]];
            }
            if (item[@"method"]) {
                [content appendFormat:@"方法: %@\n", item[@"method"]];
            }
            if (item[@"request_headers"] && [item[@"request_headers"] count] > 0) {
                [content appendFormat:@"请求头: %@\n", item[@"request_headers"]];
            }
            if (item[@"response_body"]) {
                NSString *resp = item[@"response_body"];
                if ([resp length] > 500) {
                    [content appendFormat:@"响应体: %@...\n", [resp substringToIndex:500]];
                } else {
                    [content appendFormat:@"响应体: %@\n", resp];
                }
            }
            [content appendString:@"\n"];
        }

        if (capturedData.count == 0) {
            [content appendString:@"暂无数据，请刷新个人主页"];
        }

        textView.text = content;
        [dataWindow addSubview:textView];

        // 关闭按钮
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(frame.size.width - 70, 10, 60, 30);
        [closeBtn setTitle:@"关闭" forState:UIControlStateNormal];
        [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [closeBtn addTarget:closeBtn action:@selector(tkc_closeWindow) forControlEvents:UIControlEventTouchUpInside];
        [dataWindow addSubview:closeBtn];

        [dataWindow makeKeyAndVisible];
    });
}

static void closeDataWindow() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (dataWindow) {
            [dataWindow removeFromSuperview];
            dataWindow = nil;
        }
    });
}

// ==================== Hook NSJSONSerialization ====================

%hook NSJSONSerialization

+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    id result = %orig;

    if (result && data.length > 100) {
        @try {
            NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

            if (jsonStr) {
                // 检查是否有最近的 profile/self/v1 捕获记录（2秒内）
                NSDictionary *lastCapture = pendingRequests[@"last_profile_capture"];
                if (lastCapture) {
                    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
                    NSTimeInterval captureTime = [lastCapture[@"timestamp"] doubleValue];

                    // 如果在 2 秒内，且 JSON 包含用户数据特征
                    if (now - captureTime < 2.0 && ([jsonStr containsString:@"user"] || [jsonStr containsString:@"data"])) {
                        NSNumber *captureId = lastCapture[@"id"];

                        // 找到对应的 capture 记录并追加响应体
                        for (NSMutableDictionary *item in capturedData) {
                            if ([item[@"id"] isEqual:captureId]) {
                                item[@"response_body"] = jsonStr;

                                NSLog(@"[TKCapture] ✓ Linked response body to capture #%@, size: %lu bytes",
                                    captureId, (unsigned long)data.length);

                                // 清除标记，避免重复关联
                                [pendingRequests removeObjectForKey:@"last_profile_capture"];
                                break;
                            }
                        }
                    }
                }

                // 兼容旧的 author_stats 捕获
                if ([jsonStr containsString:@"author_stats"]) {
                    captureCount++;

                    NSMutableDictionary *capture = [NSMutableDictionary new];
                    capture[@"id"] = @(captureCount);
                    capture[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
                    capture[@"type"] = @"response_json";
                    capture[@"response"] = jsonStr;

                    [capturedData addObject:capture];

                    NSLog(@"[TKCapture] ★★★ JSON #%d (size: %lu)",
                        captureCount, (unsigned long)data.length);
                }
            }
        } @catch (NSException *e) {}
    }

    return result;
}

%end

// ==================== Hook NSURLConnection ====================

%hook NSURLConnection

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error {
    if (request) {
        NSURL *url = [request URL];
        NSString *urlStr = [url absoluteString];

        if ([urlStr containsString:@"profile/self/v1"]) {
            captureCount++;

            NSMutableDictionary *capture = [NSMutableDictionary new];
            capture[@"id"] = @(captureCount);
            capture[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
            capture[@"type"] = @"request_sync";
            capture[@"url"] = urlStr;
            capture[@"method"] = [request HTTPMethod] ?: @"GET";
            capture[@"headers"] = [request allHTTPHeaderFields] ?: @{};
            capture[@"body"] = [request HTTPBody] ? [[NSString alloc] initWithData:[request HTTPBody] encoding:NSUTF8StringEncoding] : @"";

            [capturedData addObject:capture];
            NSLog(@"[TKCapture] ★ Sync Request #%d: %@", captureCount, urlStr);
        }
    }

    return %orig;
}

%end

// ==================== Hook NSURLSessionTask ====================

%hook NSURLSessionTask

- (void)resume {
    NSURLRequest *request = [self currentRequest];
    if (!request) request = [self originalRequest];

    if (request) {
        NSURL *url = [request URL];
        NSString *urlStr = [url absoluteString];

        if ([urlStr containsString:@"profile/self/v1"]) {
            captureCount++;

            NSMutableDictionary *capture = [NSMutableDictionary new];
            capture[@"id"] = @(captureCount);
            capture[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
            capture[@"type"] = @"request_task";
            capture[@"url"] = urlStr;
            capture[@"method"] = [request HTTPMethod] ?: @"GET";

            // ★★★ 捕获请求头 ★★★
            NSDictionary *headers = [request allHTTPHeaderFields];
            if (headers && headers.count > 0) {
                capture[@"request_headers"] = headers;
                NSLog(@"[TKCapture] ✓✓✓ NSURLSessionTask captured %lu request headers", (unsigned long)headers.count);
            } else {
                NSLog(@"[TKCapture] ✗ NSURLSessionTask: allHTTPHeaderFields is empty");
            }

            capture[@"body"] = [request HTTPBody] ? [[NSString alloc] initWithData:[request HTTPBody] encoding:NSUTF8StringEncoding] : @"";

            [capturedData addObject:capture];
            NSLog(@"[TKCapture] ★ Task Request #%d: %@", captureCount, urlStr);
            NSLog(@"[TKCapture]   Headers count: %lu", (unsigned long)headers.count);
        }
    }

    %orig;
}

%end

// ==================== Hook NSURLRequest ====================

%hook NSURLRequest

- (instancetype)initWithURL:(NSURL *)url {
    id result = %orig;

    if (url) {
        NSString *urlStr = [url absoluteString];
        if ([urlStr containsString:@"profile/self/v1"]) {
            // 保存请求信息到 pendingRequests，等待响应关联
            if (!pendingRequests) {
                pendingRequests = [NSMutableDictionary new];
            }

            NSString *threadId = [NSString stringWithFormat:@"%p", [NSThread currentThread]];
            pendingRequests[threadId] = @{
                @"url": urlStr,
                @"headers": [self allHTTPHeaderFields] ?: @{},
                @"timestamp": @([[NSDate date] timeIntervalSince1970])
            };

            NSLog(@"[TKCapture] → Request created: %@", urlStr);
            NSLog(@"[TKCapture] → Request Headers: %@", [self allHTTPHeaderFields]);
        }
    }

    return result;
}

- (instancetype)initWithURL:(NSURL *)url cachePolicy:(NSURLRequestCachePolicy)policy timeoutInterval:(NSTimeInterval)timeout {
    id result = %orig;

    if (url) {
        NSString *urlStr = [url absoluteString];
        if ([urlStr containsString:@"profile/self/v1"]) {
            // 保存请求信息到 pendingRequests，等待响应关联
            if (!pendingRequests) {
                pendingRequests = [NSMutableDictionary new];
            }

            NSString *threadId = [NSString stringWithFormat:@"%p", [NSThread currentThread]];
            pendingRequests[threadId] = @{
                @"url": urlStr,
                @"headers": [self allHTTPHeaderFields] ?: @{},
                @"timestamp": @([[NSDate date] timeIntervalSince1970])
            };

            NSLog(@"[TKCapture] → Request created (with policy): %@", urlStr);
            NSLog(@"[TKCapture] → Request Headers: %@", [self allHTTPHeaderFields]);
        }
    }

    return result;
}

%end

// ==================== Hook NSMutableURLRequest ====================

%hook NSMutableURLRequest

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    %orig;

    NSURL *url = [self URL];
    if (url) {
        NSString *urlStr = [url absoluteString];
        if ([urlStr containsString:@"profile/self/v1"]) {
            // 更新 pendingRequests 中的请求头
            if (!pendingRequests) {
                pendingRequests = [NSMutableDictionary new];
            }

            NSString *threadId = [NSString stringWithFormat:@"%p", [NSThread currentThread]];
            NSMutableDictionary *pending = pendingRequests[threadId];

            if (!pending) {
                pending = [NSMutableDictionary new];
                pending[@"url"] = urlStr;
                pending[@"headers"] = [NSMutableDictionary new];
                pending[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
                pendingRequests[threadId] = pending;
            }

            NSMutableDictionary *headers = pending[@"headers"];
            if (!headers) {
                headers = [NSMutableDictionary new];
                pending[@"headers"] = headers;
            }
            headers[field] = value;

            NSLog(@"[TKCapture] → Header set: %@ = %@", field, value);
        }
    }
}

- (void)setHTTPBody:(NSData *)body {
    %orig;

    NSURL *url = [self URL];
    if (url) {
        NSString *urlStr = [url absoluteString];
        if ([urlStr containsString:@"profile/self/v1"]) {
            NSMutableDictionary *capture = [NSMutableDictionary new];
            capture[@"id"] = @(++captureCount);
            capture[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
            capture[@"type"] = @"request_body";
            capture[@"url"] = urlStr;
            capture[@"method"] = [self HTTPMethod] ?: @"POST";
            capture[@"headers"] = [self allHTTPHeaderFields] ?: @{};
            capture[@"body"] = body ? [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] : @"";

            [capturedData addObject:capture];
            NSLog(@"[TKCapture] ★ Request Body #%d: %lu bytes", captureCount, (unsigned long)body.length);
        }
    }
}

%end

// ==================== Hook TTHttpResponseChromium ====================

%hook TTHttpResponseChromium

- (NSDictionary *)allHeaderFields {
    NSDictionary *headers = %orig;

    // 获取当前对象的 URL
    NSURL *url = [self URL];

    if (url) {
        NSString *urlStr = [url absoluteString];

        if ([urlStr containsString:@"profile/self/v1"]) {
            captureCount++;

            NSMutableDictionary *capture = [NSMutableDictionary new];
            capture[@"id"] = @(captureCount);
            capture[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
            capture[@"type"] = @"response_complete";
            capture[@"url"] = urlStr;
            capture[@"response_headers"] = headers ?: @{};
            capture[@"method"] = @"GET";  // profile/self/v1 是 GET 请求

            // 尝试从 pendingRequests 获取之前保存的请求头
            NSDictionary *pendingReq = pendingRequests[urlStr];
            if (pendingReq && [pendingReq[@"url"] isEqualToString:urlStr]) {
                capture[@"request_headers"] = pendingReq[@"request_headers"] ?: @{};
                NSLog(@"[TKCapture] ✓ Found request headers from TTHttpTask: %lu headers", (unsigned long)[capture[@"request_headers"] count]);
            } else {
                NSLog(@"[TKCapture] ✗ No request headers in pending cache for URL");

                // ★★★ 增强版反射：遍历所有 ivar，不限定名字 ★★★
                @try {
                    unsigned int ivarCount = 0;
                    Ivar *ivars = class_copyIvarList([self class], &ivarCount);

                    NSLog(@"[TKCapture] Scanning %u ivars in TTHttpResponseChromium...", ivarCount);

                    for (unsigned int i = 0; i < ivarCount; i++) {
                        Ivar ivar = ivars[i];
                        const char *ivarName = ivar_getName(ivar);
                        const char *ivarType = ivar_getTypeEncoding(ivar);
                        NSString *name = [NSString stringWithUTF8String:ivarName];
                        NSString *type = [NSString stringWithUTF8String:ivarType];

                        id value = object_getIvar(self, ivar);

                        if (!value) continue;

                        // 打印所有非空 ivar
                        NSLog(@"[TKCapture]   ivar[%u]: %@ (type: %@, class: %@)",
                            i, name, type, NSStringFromClass([value class]));

                        // 方案1: 直接查找 NSURLRequest
                        if ([value isKindOfClass:[NSURLRequest class]]) {
                            NSURLRequest *request = (NSURLRequest *)value;
                            NSDictionary *reqHeaders = [request allHTTPHeaderFields];
                            if (reqHeaders && reqHeaders.count > 0) {
                                capture[@"request_headers"] = reqHeaders;
                                NSLog(@"[TKCapture] ✓✓✓ Found NSURLRequest in ivar: %@", name);
                                break;
                            }
                        }

                        // 方案2: 查找包含 request 的对象，递归读取其属性
                        if ([name.lowercaseString containsString:@"task"] ||
                            [name.lowercaseString containsString:@"connection"] ||
                            [name.lowercaseString containsString:@"http"]) {

                            // 尝试调用 request 方法
                            if ([value respondsToSelector:@selector(request)]) {
                                id requestObj = [value performSelector:@selector(request)];
                                if ([requestObj isKindOfClass:[NSURLRequest class]]) {
                                    NSURLRequest *request = (NSURLRequest *)requestObj;
                                    NSDictionary *reqHeaders = [request allHTTPHeaderFields];
                                    if (reqHeaders && reqHeaders.count > 0) {
                                        capture[@"request_headers"] = reqHeaders;
                                        NSLog(@"[TKCapture] ✓✓✓ Found request via -request method on ivar: %@", name);
                                        break;
                                    }
                                }
                            }

                            // 尝试调用 currentRequest
                            if ([value respondsToSelector:@selector(currentRequest)]) {
                                id requestObj = [value performSelector:@selector(currentRequest)];
                                if ([requestObj isKindOfClass:[NSURLRequest class]]) {
                                    NSURLRequest *request = (NSURLRequest *)requestObj;
                                    NSDictionary *reqHeaders = [request allHTTPHeaderFields];
                                    if (reqHeaders && reqHeaders.count > 0) {
                                        capture[@"request_headers"] = reqHeaders;
                                        NSLog(@"[TKCapture] ✓✓✓ Found request via -currentRequest on ivar: %@", name);
                                        break;
                                    }
                                }
                            }
                        }
                    }

                    if (ivars) free(ivars);
                } @catch (NSException *e) {
                    NSLog(@"[TKCapture] Exception while finding request: %@", e);
                }
            }

            [capturedData addObject:capture];

            // 保存到 pendingRequests 用于关联响应体
            if (!pendingRequests) {
                pendingRequests = [NSMutableDictionary new];
            }
            pendingRequests[@"last_profile_capture"] = @{
                @"id": @(captureCount),
                @"timestamp": capture[@"timestamp"],
                @"url": urlStr
            };

            dispatch_async(dispatch_get_main_queue(), ^{
                if (floatingButton) {
                    [floatingButton setTitle:[NSString stringWithFormat:@"%d", captureCount] forState:UIControlStateNormal];
                }
            });

            NSLog(@"[TKCapture] ★★★ Response #%d: %@", captureCount, urlStr);
            NSLog(@"[TKCapture] Response Headers: %@", headers);
        }
    }

    return headers;
}

%end

// ==================== Hook TTHttpTask (完整请求响应捕获) ====================

%hook TTHttpTask

- (void)resume {
    @try {
        // 获取请求对象
        NSURLRequest *request = [self request];

        if (request) {
            NSURL *url = [request URL];
            NSString *urlStr = [url absoluteString];

            // 只捕获 profile/self/v1 接口
            if ([urlStr containsString:@"profile/self/v1"]) {
                captureCount++;

                // 创建请求记录
                NSMutableDictionary *capture = [NSMutableDictionary new];
                capture[@"id"] = @(captureCount);
                capture[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
                capture[@"type"] = @"tthttptask";

                // ★★★ 捕获完整 URL（包含所有参数）★★★
                capture[@"url"] = urlStr;

                // 捕获请求方法
                NSString *method = [request HTTPMethod] ?: @"GET";
                capture[@"method"] = method;

                // ★★★ 捕获请求头 ★★★
                NSDictionary *headers = [request allHTTPHeaderFields];
                if (headers && headers.count > 0) {
                    capture[@"request_headers"] = headers;
                    NSLog(@"[TKCapture] ✓✓✓ TTHttpTask captured %lu request headers", (unsigned long)headers.count);
                } else {
                    NSLog(@"[TKCapture] ✗ TTHttpTask: request.allHTTPHeaderFields is empty");
                }

                // 保存到 pendingRequests，用 URL 作为 key 方便响应时关联
                if (!pendingRequests) {
                    pendingRequests = [NSMutableDictionary new];
                }
                pendingRequests[urlStr] = capture;

                NSLog(@"[TKCapture] ★★★ TTHttpTask Request #%d", captureCount);
                NSLog(@"[TKCapture]   URL: %@", urlStr);
                NSLog(@"[TKCapture]   Method: %@", method);
                NSLog(@"[TKCapture]   Headers count: %lu", (unsigned long)[headers count]);

                // 打印请求头详情（前5个）
                int printCount = 0;
                for (NSString *key in headers) {
                    if (printCount++ < 5) {
                        NSLog(@"[TKCapture]   Header: %@ = %@", key, headers[key]);
                    }
                }
            }
        } else {
            NSLog(@"[TKCapture] ✗ TTHttpTask.resume: [self request] returned nil");
        }
    } @catch (NSException *e) {
        NSLog(@"[TKCapture] Exception in TTHttpTask resume: %@", e);
    }

    %orig;
}

- (void)readDataOfMinLength:(NSUInteger)minBytes maxLength:(NSUInteger)maxBytes timeout:(NSTimeInterval)timeout completionHandler:(void (^)(NSData *data, BOOL atEOF, NSError *error))completionHandler {

    // 保存原始 completion handler
    void (^originalHandler)(NSData *, BOOL, NSError *) = completionHandler;

    // 创建新的 completion handler 来拦截响应数据
    void (^newHandler)(NSData *, BOOL, NSError *) = ^(NSData *data, BOOL atEOF, NSError *error) {

        @try {
            if (data && data.length > 0) {
                // 获取请求对象来找到 URL
                NSURLRequest *request = [self request];
                if (request) {
                    NSString *urlStr = [[request URL] absoluteString];
                    NSMutableDictionary *capture = pendingRequests[urlStr];

                    if (capture) {
                        // 尝试解析为字符串
                        NSString *responseStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

                        if (responseStr) {
                            // 如果已有响应体，追加
                            if (capture[@"response_body"]) {
                                capture[@"response_body"] = [capture[@"response_body"] stringByAppendingString:responseStr];
                            } else {
                                capture[@"response_body"] = responseStr;
                            }

                            NSLog(@"[TKCapture] ★★★ Response data: %lu bytes (EOF: %d)", (unsigned long)data.length, atEOF);
                        }

                        // 如果是最后一块数据，保存完整记录
                        if (atEOF) {
                            [capturedData addObject:capture];
                            [pendingRequests removeObjectForKey:urlStr];

                            // 更新悬浮按钮数字
                            dispatch_async(dispatch_get_main_queue(), ^{
                                if (floatingButton) {
                                    [floatingButton setTitle:[NSString stringWithFormat:@"%d", (int)capturedData.count] forState:UIControlStateNormal];
                                }
                            });

                            NSLog(@"[TKCapture] ✓ Complete capture saved (ID: %@)", capture[@"id"]);
                        }
                    }
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[TKCapture] Exception in completion handler: %@", e);
        }

        // 调用原始 handler
        if (originalHandler) {
            originalHandler(data, atEOF, error);
        }
    };

    %orig(minBytes, maxBytes, timeout, newHandler);
}

%end

// ==================== 构造函数 ====================

// ==================== Hook NSURL initWithString ====================

%hook NSURL

- (instancetype)initWithString:(NSString *)URLString {
    id result = %orig;

    if (URLString && ([URLString containsString:@"profile"] || [URLString containsString:@"self"])
        && [URLString containsString:@"tiktok"]) {

        captureCount++;

        NSMutableDictionary *capture = [NSMutableDictionary new];
        capture[@"id"] = @(captureCount);
        capture[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
        capture[@"type"] = @"url_init";
        capture[@"url"] = URLString;

        // 获取调用栈
        NSArray *callStack = [NSThread callStackSymbols];
        if (callStack.count > 2) {
            capture[@"caller"] = callStack[2];
        }

        [capturedData addObject:capture];
        NSLog(@"[TKCapture] ★ NSURL init: %@", URLString);
    }

    return result;
}

%end

// ==================== 调试函数：验证类和方法 ====================

static void debugNetworkClasses() {
    NSLog(@"[TKCapture] ==================== CLASS DEBUG ====================");

    // 1. 验证 TTHttpTask 类是否存在
    Class ttHttpTaskClass = objc_getClass("TTHttpTask");
    if (ttHttpTaskClass) {
        NSLog(@"[TKCapture] ✓ TTHttpTask class EXISTS");

        // 打印所有实例方法
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(ttHttpTaskClass, &methodCount);
        NSLog(@"[TKCapture] TTHttpTask has %u instance methods", methodCount);

        int relevantCount = 0;
        for (unsigned int i = 0; i < methodCount && relevantCount < 20; i++) {
            SEL selector = method_getName(methods[i]);
            NSString *methodName = NSStringFromSelector(selector);

            // 只打印包含关键词的方法
            if ([methodName.lowercaseString containsString:@"request"] ||
                [methodName.lowercaseString containsString:@"resume"] ||
                [methodName.lowercaseString containsString:@"send"] ||
                [methodName.lowercaseString containsString:@"start"] ||
                [methodName.lowercaseString containsString:@"header"]) {
                NSLog(@"[TKCapture]   method: %@", methodName);
                relevantCount++;
            }
        }

        if (methods) free(methods);
    } else {
        NSLog(@"[TKCapture] ✗ TTHttpTask class NOT FOUND - searching alternatives...");

        // 搜索可能的替代类名
        unsigned int classCount = 0;
        Class *classes = objc_copyClassList(&classCount);

        int foundCount = 0;
        for (unsigned int i = 0; i < classCount && foundCount < 50; i++) {
            const char *className = class_getName(classes[i]);
            NSString *name = [NSString stringWithUTF8String:className];

            // 查找 TikTok 的网络类
            if (([name containsString:@"TT"] && ([name containsString:@"Http"] || [name containsString:@"Network"] || [name containsString:@"Request"])) ||
                ([name containsString:@"AWE"] && ([name containsString:@"Http"] || [name containsString:@"Network"]))) {
                NSLog(@"[TKCapture]   alternative: %@", name);
                foundCount++;
            }
        }

        if (classes) free(classes);
    }

    // 2. 验证 TTHttpResponseChromium 类
    Class ttHttpResponseClass = objc_getClass("TTHttpResponseChromium");
    if (ttHttpResponseClass) {
        NSLog(@"[TKCapture] ✓ TTHttpResponseChromium class EXISTS");

        // 打印所有 ivar
        unsigned int ivarCount = 0;
        Ivar *ivars = class_copyIvarList(ttHttpResponseClass, &ivarCount);
        NSLog(@"[TKCapture] TTHttpResponseChromium has %u ivars:", ivarCount);

        for (unsigned int i = 0; i < ivarCount; i++) {
            Ivar ivar = ivars[i];
            const char *ivarName = ivar_getName(ivar);
            const char *ivarType = ivar_getTypeEncoding(ivar);
            NSLog(@"[TKCapture]   ivar: %s (type: %s)", ivarName, ivarType);
        }

        if (ivars) free(ivars);
    } else {
        NSLog(@"[TKCapture] ✗ TTHttpResponseChromium class NOT FOUND");
    }

    NSLog(@"[TKCapture] ==================== END DEBUG ====================");
}

__attribute__((constructor))
static void init() {
    NSLog(@"[TKCapture] ✓ Loaded");

    capturedData = [NSMutableArray new];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        // 运行调试函数
        debugNetworkClasses();

        setupLocalServer();
        createFloatingButton();
    });
}
