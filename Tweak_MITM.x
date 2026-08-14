#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <substrate.h>

// ==================== HTTP 代理服务器 ====================

@interface MITMProxyServer : NSObject
@property (nonatomic, strong) NSMutableArray *capturedRequests;
@property (nonatomic, assign) uint16_t proxyPort;
@property (nonatomic, assign) uint16_t webPort;
+ (instancetype)sharedInstance;
- (void)startProxy;
- (void)startWebInterface;
- (NSString *)generateHTML;
@end

static MITMProxyServer *proxyServer = nil;

@implementation MITMProxyServer

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        proxyServer = [[self alloc] init];
    });
    return proxyServer;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.capturedRequests = [NSMutableArray array];
        self.proxyPort = 8899;  // 内部代理端口
        self.webPort = 9999;    // Web 界面端口
    }
    return self;
}

- (void)startProxy {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"[MITM] Starting proxy server on port %d...", self.proxyPort);

        // 创建 socket 监听
        int serverSocket = socket(AF_INET, SOCK_STREAM, 0);
        if (serverSocket < 0) {
            NSLog(@"[MITM] Failed to create socket");
            return;
        }

        int reuse = 1;
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

        struct sockaddr_in serverAddr;
        memset(&serverAddr, 0, sizeof(serverAddr));
        serverAddr.sin_family = AF_INET;
        serverAddr.sin_addr.s_addr = INADDR_ANY;
        serverAddr.sin_port = htons(self.proxyPort);

        if (bind(serverSocket, (struct sockaddr *)&serverAddr, sizeof(serverAddr)) < 0) {
            NSLog(@"[MITM] Failed to bind socket");
            close(serverSocket);
            return;
        }

        if (listen(serverSocket, 10) < 0) {
            NSLog(@"[MITM] Failed to listen");
            close(serverSocket);
            return;
        }

        NSLog(@"[MITM] Proxy server listening on 0.0.0.0:%d", self.proxyPort);

        while (YES) {
            struct sockaddr_in clientAddr;
            socklen_t clientLen = sizeof(clientAddr);
            int clientSocket = accept(serverSocket, (struct sockaddr *)&clientAddr, &clientLen);

            if (clientSocket < 0) {
                continue;
            }

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self handleClient:clientSocket];
            });
        }
    });
}

- (void)handleClient:(int)clientSocket {
    char buffer[8192];
    ssize_t bytesRead = recv(clientSocket, buffer, sizeof(buffer) - 1, 0);

    if (bytesRead <= 0) {
        close(clientSocket);
        return;
    }

    buffer[bytesRead] = '\0';
    NSString *requestStr = [NSString stringWithUTF8String:buffer];

    // 解析 HTTP 请求
    NSArray *lines = [requestStr componentsSeparatedByString:@"\r\n"];
    if (lines.count == 0) {
        close(clientSocket);
        return;
    }

    NSString *requestLine = lines[0];
    NSLog(@"[MITM] Request: %@", requestLine);

    // 解析请求头
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    NSString *body = @"";
    BOOL inBody = NO;

    for (NSUInteger i = 1; i < lines.count; i++) {
        NSString *line = lines[i];

        if (line.length == 0) {
            inBody = YES;
            continue;
        }

        if (inBody) {
            body = [body stringByAppendingString:line];
        } else {
            NSArray *parts = [line componentsSeparatedByString:@": "];
            if (parts.count >= 2) {
                headers[parts[0]] = parts[1];
            }
        }
    }

    // 检查是否是 profile/self/v1
    if ([requestLine containsString:@"profile/self/v1"]) {
        NSLog(@"[MITM] ★★★ CAPTURED profile/self/v1 ★★★");

        @synchronized (self.capturedRequests) {
            [self.capturedRequests addObject:@{
                @"time": [NSDate date],
                @"request": requestLine,
                @"headers": headers,
                @"body": body
            }];

            // 只保留最近 50 条
            if (self.capturedRequests.count > 50) {
                [self.capturedRequests removeObjectAtIndex:0];
            }
        }
    }

    // 转发请求到真实服务器
    // TODO: 这里需要实现真实的转发逻辑

    // 简单返回 200
    NSString *response = @"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK";
    send(clientSocket, [response UTF8String], response.length, 0);
    close(clientSocket);
}

- (void)startWebInterface {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"[MITM] Starting web interface on port %d...", self.webPort);

        int serverSocket = socket(AF_INET, SOCK_STREAM, 0);
        if (serverSocket < 0) {
            NSLog(@"[MITM] Failed to create web socket");
            return;
        }

        int reuse = 1;
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

        struct sockaddr_in serverAddr;
        memset(&serverAddr, 0, sizeof(serverAddr));
        serverAddr.sin_family = AF_INET;
        serverAddr.sin_addr.s_addr = INADDR_ANY;
        serverAddr.sin_port = htons(self.webPort);

        if (bind(serverSocket, (struct sockaddr *)&serverAddr, sizeof(serverAddr)) < 0) {
            NSLog(@"[MITM] Failed to bind web socket");
            close(serverSocket);
            return;
        }

        if (listen(serverSocket, 10) < 0) {
            NSLog(@"[MITM] Failed to listen on web socket");
            close(serverSocket);
            return;
        }

        NSLog(@"[MITM] Web interface ready at http://192.168.9.102:%d/", self.webPort);

        while (YES) {
            struct sockaddr_in clientAddr;
            socklen_t clientLen = sizeof(clientAddr);
            int clientSocket = accept(serverSocket, (struct sockaddr *)&clientAddr, &clientLen);

            if (clientSocket < 0) {
                continue;
            }

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self handleWebClient:clientSocket];
            });
        }
    });
}

- (void)handleWebClient:(int)clientSocket {
    char buffer[4096];
    recv(clientSocket, buffer, sizeof(buffer) - 1, 0);

    NSString *html = [self generateHTML];
    NSString *response = [NSString stringWithFormat:
        @"HTTP/1.1 200 OK\r\n"
        @"Content-Type: text/html; charset=utf-8\r\n"
        @"Content-Length: %lu\r\n"
        @"Connection: close\r\n"
        @"\r\n%@",
        (unsigned long)html.length, html
    ];

    send(clientSocket, [response UTF8String], response.length, 0);
    close(clientSocket);
}

- (NSString *)generateHTML {
    NSMutableString *html = [NSMutableString string];

    [html appendString:@"<!DOCTYPE html><html><head><meta charset='utf-8'>"];
    [html appendString:@"<meta name='viewport' content='width=device-width,initial-scale=1'>"];
    [html appendString:@"<title>TikTok MITM Proxy</title>"];
    [html appendString:@"<style>"];
    [html appendString:@"body{font-family:monospace;padding:20px;background:#1e1e1e;color:#d4d4d4;}"];
    [html appendString:@"h1{color:#4ec9b0;}"];
    [html appendString:@".request{background:#252526;border:1px solid #3e3e42;padding:15px;margin:10px 0;border-radius:5px;}"];
    [html appendString:@".time{color:#608b4e;}"];
    [html appendString:@".url{color:#4fc1ff;word-break:break-all;}"];
    [html appendString:@".header{color:#ce9178;margin:5px 0;}"];
    [html appendString:@"</style></head><body>"];
    [html appendString:@"<h1>🚀 TikTok MITM Proxy</h1>"];
    [html appendFormat:@"<p>Captured: <b>%lu</b> requests</p>", (unsigned long)self.capturedRequests.count];

    @synchronized (self.capturedRequests) {
        for (NSDictionary *req in [self.capturedRequests reverseObjectEnumerator]) {
            [html appendString:@"<div class='request'>"];
            [html appendFormat:@"<div class='time'>%@</div>", req[@"time"]];
            [html appendFormat:@"<div class='url'>%@</div>", req[@"request"]];
            [html appendString:@"<div><b>Headers:</b></div>"];

            NSDictionary *headers = req[@"headers"];
            for (NSString *key in headers) {
                [html appendFormat:@"<div class='header'>  %@: %@</div>", key, headers[key]];
            }

            [html appendString:@"</div>"];
        }
    }

    [html appendString:@"<script>setTimeout(()=>location.reload(),3000);</script>"];
    [html appendString:@"</body></html>"];

    return html;
}

@end

// ==================== Hook 实现 ====================

%hook TTHttpTask

- (void)setSkipSSLCertificateError:(BOOL)skip {
    NSLog(@"[MITM] setSkipSSLCertificateError called, forcing YES");
    %orig(YES);  // 强制跳过证书验证
}

%end

%hook NSURLSessionConfiguration

- (NSDictionary *)connectionProxyDictionary {
    NSDictionary *orig = %orig;

    // 强制设置代理到我们的本地代理服务器
    NSDictionary *proxy = @{
        @"HTTPEnable": @1,
        @"HTTPProxy": @"127.0.0.1",
        @"HTTPPort": @8899,
        @"HTTPSEnable": @1,
        @"HTTPSProxy": @"127.0.0.1",
        @"HTTPSPort": @8899
    };

    NSLog(@"[MITM] Injecting proxy configuration");
    return proxy;
}

%end

// ==================== 初始化 ====================

%ctor {
    NSLog(@"[MITM] TikTok MITM Proxy loaded");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        MITMProxyServer *server = [MITMProxyServer sharedInstance];
        [server startProxy];
        [server startWebInterface];

        NSLog(@"[MITM] ✓ All services started");
        NSLog(@"[MITM] ✓ Web interface: http://192.168.9.102:9999/");
    });
}
