#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <substrate.h>

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
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) {
        keyWindow = [UIApplication sharedApplication].windows.firstObject;
    }
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
+ (instancetype)shared;
- (void)startProxy;
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
    }

    // 返回简单响应（实际应该转发）
    const char *resp = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK";
    send(client, resp, strlen(resp), 0);
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

        NSLog(@"[MITM] ✅ All services started");
        NSLog(@"[MITM] 📱 Refresh TikTok profile page now!");
    });
}
