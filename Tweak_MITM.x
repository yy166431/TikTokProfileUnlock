#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <ifaddrs.h>
#import <netdb.h>

// ==================== 悬浮窗 ====================

@interface FloatingButton : UIButton
@property (nonatomic, strong) UILabel *statusLabel;
+ (instancetype)sharedButton;
- (void)show;
- (void)updateStatus:(NSString *)status;
@end

static FloatingButton *floatingButton = nil;

@implementation FloatingButton

+ (instancetype)sharedButton {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        floatingButton = [[self alloc] initWithFrame:CGRectMake(20, 100, 120, 80)];
        [floatingButton setup];
    });
    return floatingButton;
}

- (void)setup {
    self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
    self.layer.cornerRadius = 10;
    self.layer.borderWidth = 2;
    self.layer.borderColor = [UIColor greenColor].CGColor;

    self.statusLabel = [[UILabel alloc] initWithFrame:self.bounds];
    self.statusLabel.text = @"🎯 MITM\n等待中...";
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.font = [UIFont boldSystemFontOfSize:12];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    [self addSubview:self.statusLabel];

    // 添加拖动手势
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];
}

- (void)show {
    UIWindow *keyWindow = nil;

    // iOS 13+ 兼容
    if (@available(iOS 13.0, *)) {
        NSSet *scenes = [UIApplication sharedApplication].connectedScenes;
        for (UIWindowScene *scene in scenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                keyWindow = scene.windows.firstObject;
                break;
            }
        }
    }

    if (!keyWindow) {
        keyWindow = [UIApplication sharedApplication].windows.firstObject;
    }

    if (!keyWindow) return;

    [keyWindow addSubview:self];
    [keyWindow bringSubviewToFront:self];
}

- (void)updateStatus:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = status;

        // 成功时变绿
        if ([status containsString:@"✅"]) {
            self.layer.borderColor = [UIColor greenColor].CGColor;
            self.backgroundColor = [[UIColor greenColor] colorWithAlphaComponent:0.3];
        }
    });
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:self.superview];
        self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
        [gesture setTranslation:CGPointZero inView:self.superview];
    }
}

@end

// ==================== 代理服务器 ====================

@interface MITMProxy : NSObject
@property (nonatomic, assign) BOOL captured;
@property (nonatomic, strong) NSString *capturedData;
+ (instancetype)shared;
- (void)startProxy;
- (void)startWebServer;
- (void)saveData:(NSString *)url headers:(NSDictionary *)headers body:(NSString *)body;
@end

static MITMProxy *proxy = nil;

@implementation MITMProxy

+ (instancetype)shared {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        proxy = [[self alloc] init];
    });
    return proxy;
}

- (void)startProxy {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSLog(@"[MITM] 🚀 Starting proxy on port 8899...");

        int sock = socket(AF_INET, SOCK_STREAM, 0);
        int reuse = 1;
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = INADDR_ANY;
        addr.sin_port = htons(8899);

        if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            NSLog(@"[MITM] ❌ Bind failed");
            return;
        }

        listen(sock, 10);
        NSLog(@"[MITM] ✅ Proxy listening on 0.0.0.0:8899");

        [[FloatingButton sharedButton] updateStatus:@"🎯 MITM\n代理启动"];

        while (!self.captured) {
            struct sockaddr_in clientAddr;
            socklen_t len = sizeof(clientAddr);
            int client = accept(sock, (struct sockaddr *)&clientAddr, &len);

            if (client < 0) continue;

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                [self handleClient:client];
            });
        }

        close(sock);
        NSLog(@"[MITM] 🎉 Captured! Proxy stopped.");
    });
}

- (NSString *)getLocalIPAddress {
    NSString *address = @"0.0.0.0";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;

    if (getifaddrs(&interfaces) == 0) {
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            if(temp_addr->ifa_addr->sa_family == AF_INET) {
                // Check if interface is en0 (Wi-Fi) or en1
                if([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"] ||
                   [[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en1"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    return address;
}

- (void)startWebServer {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"[MITM] 🌐 Starting web server on port 9999...");

        int sock = socket(AF_INET, SOCK_STREAM, 0);
        int reuse = 1;
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = INADDR_ANY;
        addr.sin_port = htons(9999);

        if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            NSLog(@"[MITM] ❌ Web server bind failed");
            return;
        }

        listen(sock, 10);
        NSString *localIP = [self getLocalIPAddress];
        NSLog(@"[MITM] ✅ Web server at http://%@:9999/", localIP);

        while (YES) {
            struct sockaddr_in clientAddr;
            socklen_t len = sizeof(clientAddr);
            int client = accept(sock, (struct sockaddr *)&clientAddr, &len);

            if (client < 0) continue;

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self handleWebClient:client];
            });
        }
    });
}

- (void)handleWebClient:(int)client {
    char buf[4096];
    ssize_t n = recv(client, buf, sizeof(buf) - 1, 0);

    if (n <= 0) {
        close(client);
        return;
    }

    buf[n] = '\0';
    NSString *request = [NSString stringWithUTF8String:buf];

    // 检查是否请求下载
    if ([request containsString:@"GET /download"]) {
        NSString *data = self.capturedData ?: @"No data captured yet.";
        NSData *dataBytes = [data dataUsingEncoding:NSUTF8StringEncoding];

        NSString *response = [NSString stringWithFormat:
            @"HTTP/1.1 200 OK\r\n"
            @"Content-Type: text/plain; charset=utf-8\r\n"
            @"Content-Disposition: attachment; filename=\"tiktok_capture.txt\"\r\n"
            @"Content-Length: %lu\r\n"
            @"Connection: close\r\n"
            @"\r\n",
            (unsigned long)dataBytes.length
        ];

        send(client, [response UTF8String], response.length, 0);
        send(client, dataBytes.bytes, dataBytes.length, 0);
    } else {
        // 返回 HTML 界面
        NSString *html = [self generateHTML];
        NSString *response = [NSString stringWithFormat:
            @"HTTP/1.1 200 OK\r\n"
            @"Content-Type: text/html; charset=utf-8\r\n"
            @"Content-Length: %lu\r\n"
            @"Connection: close\r\n"
            @"\r\n%@",
            (unsigned long)html.length, html
        ];

        send(client, [response UTF8String], response.length, 0);
    }

    close(client);
}

- (NSString *)generateHTML {
    NSString *status = self.captured ? @"✅ 已捕获" : @"⏳ 等待中...";
    NSString *color = self.captured ? @"#4ade80" : @"#fbbf24";
    NSString *data = self.capturedData ?: @"<p style='color:#666'>尚未捕获数据，请在 TikTok 内刷新个人主页...</p>";
    NSString *downloadBtn = self.captured ?
        @"<a href='/download' download='tiktok_capture.txt' style='display:inline-block;margin:20px 0;padding:15px 30px;background:#4ade80;color:#000;text-decoration:none;border-radius:8px;font-weight:bold'>📥 下载数据</a>" :
        @"";

    return [NSString stringWithFormat:
        @"<!DOCTYPE html>"
        @"<html><head>"
        @"<meta charset='utf-8'>"
        @"<meta name='viewport' content='width=device-width,initial-scale=1'>"
        @"<title>TikTok MITM Proxy</title>"
        @"<style>"
        @"*{margin:0;padding:0;box-sizing:border-box}"
        @"body{font-family:-apple-system,system-ui,sans-serif;background:#0f0f0f;color:#e5e5e5;padding:20px}"
        @"h1{font-size:24px;margin-bottom:10px}"
        @".status{display:inline-block;padding:8px 16px;background:%@;color:#000;border-radius:20px;font-weight:bold;margin-bottom:20px}"
        @"pre{background:#1a1a1a;padding:20px;border-radius:8px;overflow-x:auto;font-size:13px;line-height:1.6;border:1px solid #333}"
        @"</style>"
        @"</head><body>"
        @"<h1>🎯 TikTok MITM Proxy</h1>"
        @"<div class='status'>%@</div>"
        @"%@"
        @"<pre>%@</pre>"
        @"<script>setTimeout(()=>location.reload(),5000)</script>"
        @"</body></html>",
        color, status, downloadBtn,
        [data stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"]
    ];
}

- (void)handleClient:(int)client {
    char buf[16384];
    ssize_t n = recv(client, buf, sizeof(buf) - 1, 0);

    if (n <= 0) {
        close(client);
        return;
    }

    buf[n] = '\0';
    NSString *req = [NSString stringWithUTF8String:buf];

    // 检查是否是 profile/self/v1
    if ([req containsString:@"profile/self/v1"] || [req containsString:@"/aweme/v1/user/"]) {
        NSLog(@"[MITM] ★★★ FOUND profile/self/v1 ★★★");

        // 解析请求
        NSArray *lines = [req componentsSeparatedByString:@"\r\n"];
        NSString *requestLine = lines.firstObject;

        NSMutableDictionary *headers = [NSMutableDictionary dictionary];
        for (NSUInteger i = 1; i < lines.count; i++) {
            NSString *line = lines[i];
            if (line.length == 0) break;

            NSRange colon = [line rangeOfString:@": "];
            if (colon.location != NSNotFound) {
                NSString *key = [line substringToIndex:colon.location];
                NSString *val = [line substringFromIndex:colon.location + 2];
                headers[key] = val;
            }
        }

        // 提取 URL
        NSArray *parts = [requestLine componentsSeparatedByString:@" "];
        NSString *url = parts.count > 1 ? parts[1] : @"";

        // 保存数据
        [self saveData:url headers:headers body:@""];

        self.captured = YES;
        [[FloatingButton sharedButton] updateStatus:@"✅ 已捕获\nprofile/self"];

        // 转发到真实服务器
        [self forwardRequest:buf length:n toClient:client];
    } else {
        // 其他请求直接透明转发
        [self forwardRequest:buf length:n toClient:client];
    }
}

- (void)forwardRequest:(const char *)request length:(ssize_t)len toClient:(int)client {
    // 解析 Host 头
    NSString *req = [NSString stringWithUTF8String:request];
    NSString *host = nil;
    int port = 443;

    NSArray *lines = [req componentsSeparatedByString:@"\r\n"];
    for (NSString *line in lines) {
        if ([line hasPrefix:@"Host: "]) {
            host = [line substringFromIndex:6];
            break;
        }
    }

    if (!host) {
        close(client);
        return;
    }

    // 连接到真实服务器
    int serverSock = socket(AF_INET, SOCK_STREAM, 0);
    if (serverSock < 0) {
        close(client);
        return;
    }

    struct sockaddr_in serverAddr;
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_port = htons(port);

    // 解析 IP（简化版，实际应该用 getaddrinfo）
    const char *hostCStr = [host UTF8String];
    struct hostent *he = gethostbyname(hostCStr);
    if (!he) {
        close(serverSock);
        close(client);
        return;
    }

    memcpy(&serverAddr.sin_addr, he->h_addr_list[0], he->h_length);

    // 连接
    if (connect(serverSock, (struct sockaddr *)&serverAddr, sizeof(serverAddr)) < 0) {
        close(serverSock);
        close(client);
        return;
    }

    // 转发请求
    send(serverSock, request, len, 0);

    // 接收响应并转发回客户端
    char respBuf[16384];
    ssize_t respLen;
    while ((respLen = recv(serverSock, respBuf, sizeof(respBuf), 0)) > 0) {
        send(client, respBuf, respLen, 0);
    }

    close(serverSock);
    close(client);
}

- (void)saveData:(NSString *)url headers:(NSDictionary *)headers body:(NSString *)body {
    NSMutableString *output = [NSMutableString string];

    [output appendString:@"==================== CAPTURED ====================\n"];
    [output appendFormat:@"Time: %@\n", [NSDate date]];
    [output appendString:@"==================================================\n\n"];

    [output appendString:@"[REQUEST URL]\n"];
    [output appendFormat:@"%@\n\n", url];

    [output appendString:@"[REQUEST HEADERS]\n"];
    for (NSString *key in headers) {
        [output appendFormat:@"%@: %@\n", key, headers[key]];
    }

    [output appendString:@"\n[RESPONSE BODY]\n"];
    [output appendFormat:@"%@\n", body];

    // 保存到内存
    self.capturedData = output;

    // 保存到沙盒
    NSString *docPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *filePath = [docPath stringByAppendingPathComponent:@"tiktok_profile_captured.txt"];

    [output writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSLog(@"[MITM] 💾 Saved to: %@", filePath);
    NSLog(@"[MITM] 📊 Headers count: %lu", (unsigned long)headers.count);

    // 打印关键 headers
    NSArray *keyHeaders = @[@"x-gorgon", @"x-khronos", @"x-tt-token", @"x-ss-stub", @"User-Agent"];
    for (NSString *key in keyHeaders) {
        if (headers[key]) {
            NSLog(@"[MITM]   %@: %@", key, headers[key]);
        }
    }
}

@end

// ==================== Hooks ====================

%hook TTHttpTask

- (void)setSkipSSLCertificateError:(BOOL)skip {
    NSLog(@"[MITM] 🔓 Forcing SSL verification bypass");
    %orig(YES);
}

%end

%hook NSURLSessionConfiguration

- (NSDictionary *)connectionProxyDictionary {
    NSDictionary *proxyDict = @{
        @"HTTPEnable": @YES,
        @"HTTPProxy": @"127.0.0.1",
        @"HTTPPort": @8899,
        @"HTTPSEnable": @YES,
        @"HTTPSProxy": @"127.0.0.1",
        @"HTTPSPort": @8899
    };

    NSLog(@"[MITM] 🔀 Redirecting traffic to local proxy");
    return proxyDict;
}

%end

// ==================== 初始化 ====================

%ctor {
    NSLog(@"[MITM] 🎯 TikTok MITM Proxy v2.0 loaded");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        // 显示悬浮窗
        [[FloatingButton sharedButton] show];

        // 启动代理
        [[MITMProxy shared] startProxy];

        // 启动 Web 服务器
        [[MITMProxy shared] startWebServer];

        NSLog(@"[MITM] ✅ All services started");
        NSLog(@"[MITM] 📱 Refresh TikTok profile page now!");
        NSLog(@"[MITM] 🌐 Web UI: http://192.168.9.102:9999/");
    });
}
