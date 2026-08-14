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

// ==================== 简易 HTTP 服务器 ====================

static NSString* generateHTML() {
    NSMutableString *html = [NSMutableString new];
    [html appendString:@"<html><head><meta charset='utf-8'><title>TikTok Capture</title>"];
    [html appendString:@"<style>body{font-family:monospace;padding:20px;background:#1a1a1a;color:#0f0}"];
    [html appendString:@".item{border:1px solid #0f0;margin:10px 0;padding:10px;background:#000}"];
    [html appendString:@".url{color:#0ff;word-break:break-all}"];
    [html appendString:@".json{color:#ff0;white-space:pre-wrap;max-height:300px;overflow:auto}"];
    [html appendString:@"</style></head><body>"];
    [html appendFormat:@"<h1>TikTok Profile Capture</h1><p>捕获数量: %d</p>", (int)capturedData.count];
    [html appendString:@"<div id='list'>"];

    for (NSDictionary *item in [capturedData reverseObjectEnumerator]) {
        [html appendFormat:@"<div class='item'><b>ID:</b> %@<br><b>URL:</b> <span class='url'>%@</span><br><b>响应:</b><pre class='json'>%@</pre></div>",
            item[@"id"], item[@"url"] ?: @"N/A", item[@"response"] ?: @"N/A"];
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

// ==================== Hook NSJSONSerialization ====================

%hook NSJSONSerialization

+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    id result = %orig;

    if (result && data.length > 1000 && data.length < 100000) {
        @try {
            NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

            if (jsonStr && [jsonStr containsString:@"author_stats"]) {
                captureCount++;

                NSMutableDictionary *capture = [NSMutableDictionary new];
                capture[@"id"] = @(captureCount);
                capture[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
                capture[@"type"] = @"response";
                capture[@"url"] = @"profile/self";
                capture[@"response"] = jsonStr;

                [capturedData addObject:capture];

                NSLog(@"[TKCapture] ★★★ Captured #%d (size: %lu)",
                    captureCount, (unsigned long)data.length);
            }
        } @catch (NSException *e) {}
    }

    return result;
}

%end

// ==================== Hook TTHttpResponseChromium ====================

%hook TTHttpResponseChromium

- (instancetype)initWithURL:(NSURL *)url statusCode:(NSInteger)code HTTPVersion:(id)version headerFields:(NSDictionary *)headers {
    id result = %orig;

    if (url) {
        NSString *urlStr = [url absoluteString];

        if ([urlStr containsString:@"profile/self"]) {
            captureCount++;

            NSMutableDictionary *capture = [NSMutableDictionary new];
            capture[@"id"] = @(captureCount);
            capture[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
            capture[@"type"] = @"request";
            capture[@"url"] = urlStr;
            capture[@"statusCode"] = @(code);
            capture[@"headers"] = headers ?: @{};

            [capturedData addObject:capture];

            NSLog(@"[TKCapture] ★★★ URL #%d: %@", captureCount, urlStr);
        }
    }

    return result;
}

%end

// ==================== 构造函数 ====================

__attribute__((constructor))
static void init() {
    NSLog(@"[TKCapture] ✓ Loaded");

    capturedData = [NSMutableArray new];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        setupLocalServer();
    });
}
