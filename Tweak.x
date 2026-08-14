// TikTok Request Headers Capture - dylib version
// Extract x-argus, x-gorgon, x-khronos, x-ladon + complete URL
// HTTP Server on port 8888 + Floating button

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

#define HTTP_PORT 8888

static NSMutableArray *capturedData = nil;
static CFSocketRef serverSocket = NULL;
static int captureCount = 0;
static UIButton *floatingButton = nil;
static UIWindow *dataWindow = nil;

// ==================== memcmp Hook ====================

// Original memcmp
static int (*original_memcmp)(const void *, const void *, size_t);

// Extract headers from x26 register data
static NSString* extractValue(NSString *raw, NSString *key, int maxLen) {
    NSRange range = [raw rangeOfString:key];
    if (range.location == NSNotFound) return @"";

    NSInteger start = range.location + key.length;
    if (start >= raw.length) return @"";

    NSString *sub = [raw substringFromIndex:start];

    // Find next header marker or special char
    NSArray *markers = @[@"x-gorgon", @"x-khronos", @"x-ladon", @"x-argus", @"x-common", @"\r", @"\n", @";"];
    NSInteger minPos = maxLen < sub.length ? maxLen : sub.length;

    for (NSString *m in markers) {
        NSRange r = [sub rangeOfString:m];
        if (r.location != NSNotFound && r.location < minPos) {
            minPos = r.location;
        }
    }

    return [sub substringToIndex:minPos];
}

// Hooked memcmp - capture signatures from x26
static int hooked_memcmp(const void *s1, const void *s2, size_t n) {
    int result = original_memcmp(s1, s2, n);

    if (result != 0 || n != 8) return result;

    @autoreleasepool {
        char str1[9] = {0}, str2[9] = {0};
        memcpy(str1, s1, 8);
        memcpy(str2, s2, 8);

        if (strcmp(str1, "x-gorgon") != 0 && strcmp(str2, "x-gorgon") != 0) {
            return result;
        }

        // Get x26 register via inline assembly
        void *x26_ptr = NULL;
        __asm__ volatile("mov %0, x26" : "=r"(x26_ptr));

        if (!x26_ptr) return result;

        // Read x26 memory safely
        NSString *raw = nil;
        @try {
            const char *data = (const char *)x26_ptr;
            raw = [[NSString alloc] initWithBytes:data length:1200 encoding:NSUTF8StringEncoding];
        } @catch (NSException *e) {
            return result;
        }

        if (!raw || [raw rangeOfString:@"x-gorgon"].location == NSNotFound) {
            return result;
        }

        captureCount++;

        // Extract signature headers
        NSString *argus = extractValue(raw, @"x-argus", 200);
        NSString *gorgon = extractValue(raw, @"x-gorgon", 52);
        NSString *khronos = extractValue(raw, @"x-khronos", 10);
        NSString *ladon = extractValue(raw, @"x-ladon", 800);

        // Extract Query parameters - more permissive regex to capture full query string
        NSString *query = @"";
        NSRange musicalRange = [raw rangeOfString:@"musical_ly"];
        if (musicalRange.location != NSNotFound) {
            NSString *qStr = [raw substringFromIndex:musicalRange.location];
            // Find end of query string (before next header or line break)
            NSArray *endMarkers = @[@"\r\n", @"\n", @"x-gorgon", @"x-argus", @"x-khronos", @"x-ladon", @"HTTP/"];
            NSInteger endPos = qStr.length;
            for (NSString *marker in endMarkers) {
                NSRange r = [qStr rangeOfString:marker];
                if (r.location != NSNotFound && r.location < endPos) {
                    endPos = r.location;
                }
            }
            query = [[qStr substringToIndex:endPos] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }

        // Build complete URL
        NSString *fullURL = [NSString stringWithFormat:@"https://api-t.tiktokv.com/tiktok/user/profile/self/v1?%@", query];

        // Store captured data
        NSDictionary *item = @{
            @"id": @(captureCount),
            @"timestamp": [[NSDate date] description],
            @"url": fullURL,
            @"headers": @{
                @"x-argus": argus,
                @"x-gorgon": gorgon,
                @"x-khronos": khronos,
                @"x-ladon": ladon
            }
        };

        [capturedData addObject:item];

        // Update floating button
        dispatch_async(dispatch_get_main_queue(), ^{
            if (floatingButton) {
                [floatingButton setTitle:[NSString stringWithFormat:@"📡 %d", captureCount] forState:UIControlStateNormal];
            }
        });

        NSLog(@"[TikTokHeaders] Captured #%d: argus=%@, gorgon=%@", captureCount,
              [argus substringToIndex:MIN(20, argus.length)],
              [gorgon substringToIndex:MIN(20, gorgon.length)]);
    }

    return result;
}

// ==================== HTTP Server ====================

static NSString* generateHTML() {
    NSMutableString *html = [NSMutableString new];
    [html appendString:@"<!DOCTYPE html><html><head><meta charset='utf-8'><title>TikTok Headers</title>"];
    [html appendString:@"<style>body{font-family:monospace;padding:20px;background:#000;color:#0f0}"];
    [html appendString:@".item{border:1px solid #0f0;margin:10px 0;padding:15px;background:#111}"];
    [html appendString:@".url{color:#0ff;word-break:break-all;font-size:10px;white-space:pre-wrap}"];
    [html appendString:@".header{color:#ff0;margin:5px 0;word-break:break-all;white-space:pre-wrap}"];
    [html appendString:@".label{color:#f90;font-weight:bold}"];
    [html appendString:@"h1{color:#0ff}</style></head><body>"];
    [html appendFormat:@"<h1>TikTok Request Headers</h1><p>Captured: %d</p>", (int)capturedData.count];

    for (NSDictionary *item in [capturedData reverseObjectEnumerator]) {
        [html appendString:@"<div class='item'>"];
        [html appendFormat:@"<span class='label'>#%@</span> - %@<br>", item[@"id"], item[@"timestamp"]];
        [html appendFormat:@"<span class='label'>URL:</span><br><span class='url'>%@</span><br><br>", item[@"url"]];

        NSDictionary *headers = item[@"headers"];
        [html appendFormat:@"<div class='header'><span class='label'>x-argus:</span> %@</div>", headers[@"x-argus"]];
        [html appendFormat:@"<div class='header'><span class='label'>x-gorgon:</span> %@</div>", headers[@"x-gorgon"]];
        [html appendFormat:@"<div class='header'><span class='label'>x-khronos:</span> %@</div>", headers[@"x-khronos"]];

        NSString *ladon = headers[@"x-ladon"];
        if (ladon.length > 100) {
            [html appendFormat:@"<div class='header'><span class='label'>x-ladon:</span> %@...</div>", [ladon substringToIndex:100]];
        } else {
            [html appendFormat:@"<div class='header'><span class='label'>x-ladon:</span> %@</div>", ladon];
        }

        [html appendString:@"</div>"];
    }

    if (capturedData.count == 0) {
        [html appendString:@"<p>No data yet. Refresh TikTok profile page.</p>"];
    }

    [html appendString:@"<script>setTimeout(()=>location.reload(),3000)</script></body></html>"];
    return html;
}

static NSString* generateJSON() {
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{@"captures": capturedData, @"count": @(captureCount)}
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&error];
    if (error) return @"{\"error\":\"JSON serialization failed\"}";
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

static void handleHTTPRequest(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    if (type != kCFSocketAcceptCallBack) return;

    CFSocketNativeHandle clientSocket = *(CFSocketNativeHandle *)data;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        char buffer[2048];
        ssize_t received = recv(clientSocket, buffer, sizeof(buffer) - 1, 0);
        if (received <= 0) {
            close(clientSocket);
            return;
        }
        buffer[received] = '\0';

        NSString *request = [NSString stringWithUTF8String:buffer];
        NSString *response = nil;

        if ([request containsString:@"GET /json"]) {
            NSString *jsonStr = generateJSON();
            response = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: %lu\r\n\r\n%@",
                       (unsigned long)[jsonStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], jsonStr];
        } else {
            NSString *html = generateHTML();
            response = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %lu\r\n\r\n%@",
                       (unsigned long)[html lengthOfBytesUsingEncoding:NSUTF8StringEncoding], html];
        }

        send(clientSocket, [response UTF8String], [response lengthOfBytesUsingEncoding:NSUTF8StringEncoding], 0);
        close(clientSocket);
    });
}

static void startHTTPServer() {
    if (serverSocket) return;

    CFSocketContext context = {0, NULL, NULL, NULL, NULL};
    serverSocket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, handleHTTPRequest, &context);

    if (!serverSocket) {
        NSLog(@"[TikTokHeaders] Failed to create socket");
        return;
    }

    int yes = 1;
    setsockopt(CFSocketGetNative(serverSocket), SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(HTTP_PORT);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    CFDataRef addressData = CFDataCreate(NULL, (const UInt8 *)&addr, sizeof(addr));
    if (CFSocketSetAddress(serverSocket, addressData) != kCFSocketSuccess) {
        NSLog(@"[TikTokHeaders] Failed to bind to port %d", HTTP_PORT);
        CFRelease(serverSocket);
        serverSocket = NULL;
        CFRelease(addressData);
        return;
    }
    CFRelease(addressData);

    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, serverSocket, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CFRelease(source);

    NSLog(@"[TikTokHeaders] HTTP Server started on port %d", HTTP_PORT);
}

// ==================== Floating Button ====================

__attribute__((unused)) static void showDataWindow() {
    if (dataWindow) {
        [dataWindow makeKeyAndVisible];
        return;
    }

    dataWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 100, 350, 500)];
    dataWindow.windowLevel = UIWindowLevelAlert + 10;
    dataWindow.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.95];
    dataWindow.layer.cornerRadius = 15;
    dataWindow.clipsToBounds = YES;

    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(10, 50, 330, 400)];
    textView.backgroundColor = [UIColor blackColor];
    textView.textColor = [UIColor greenColor];
    textView.font = [UIFont fontWithName:@"Courier" size:10];
    textView.editable = NO;

    NSMutableString *text = [NSMutableString new];
    [text appendFormat:@"TikTok Headers Capture\n\nTotal: %d\n\n", captureCount];

    for (NSDictionary *item in [capturedData reverseObjectEnumerator]) {
        [text appendFormat:@"========== #%@ ==========\n", item[@"id"]];
        [text appendFormat:@"URL: %@\n\n", item[@"url"]];
        NSDictionary *h = item[@"headers"];
        [text appendFormat:@"x-argus: %@\n", h[@"x-argus"]];
        [text appendFormat:@"x-gorgon: %@\n", h[@"x-gorgon"]];
        [text appendFormat:@"x-khronos: %@\n", h[@"x-khronos"]];
        [text appendFormat:@"x-ladon: %@\n\n", [h[@"x-ladon"] substringToIndex:MIN(80, [h[@"x-ladon"] length])]];
    }

    textView.text = text;
    [dataWindow addSubview:textView];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(280, 10, 60, 30);
    [closeBtn setTitle:@"关闭" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [closeBtn addTarget:nil action:@selector(closeDataWindow) forControlEvents:UIControlEventTouchUpInside];
    [dataWindow addSubview:closeBtn];

    [dataWindow makeKeyAndVisible];
}

__attribute__((unused)) static void closeDataWindow() {
    if (dataWindow) {
        dataWindow.hidden = YES;
        dataWindow = nil;
    }
}

static void createFloatingButton() {
    if (floatingButton) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        NSArray *windows = [UIApplication sharedApplication].windows;
        for (UIWindow *window in windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        if (!keyWindow && windows.count > 0) {
            keyWindow = windows.firstObject;
        }
        if (!keyWindow) return;

        floatingButton = [UIButton buttonWithType:UIButtonTypeSystem];
        floatingButton.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 80, 100, 70, 40);
        floatingButton.backgroundColor = [UIColor colorWithRed:0 green:0.8 blue:0 alpha:0.9];
        floatingButton.layer.cornerRadius = 20;
        [floatingButton setTitle:@"📡 0" forState:UIControlStateNormal];
        [floatingButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        [floatingButton addTarget:nil action:@selector(showDataWindow) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:@selector(handlePan:)];
        [floatingButton addGestureRecognizer:pan];

        [keyWindow addSubview:floatingButton];

        NSLog(@"[TikTokHeaders] Floating button created");
    });
}

__attribute__((unused)) static void handlePan(UIPanGestureRecognizer *gesture) {
    CGPoint translation = [gesture translationInView:gesture.view.superview];
    gesture.view.center = CGPointMake(gesture.view.center.x + translation.x, gesture.view.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:gesture.view.superview];
}

// ==================== Constructor ====================

%ctor {
    @autoreleasepool {
        capturedData = [NSMutableArray new];

        NSLog(@"[TikTokHeaders] dylib loaded - memcmp hook mode");

        // Hook memcmp
        MSHookFunction((void *)memcmp, (void *)hooked_memcmp, (void **)&original_memcmp);

        NSLog(@"[TikTokHeaders] memcmp hooked successfully");

        // Start HTTP server
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            startHTTPServer();
        });

        // Create floating button
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            createFloatingButton();
        });

        NSLog(@"[TikTokHeaders] HTTP Server on port %d, access via http://192.168.9.102:8888", HTTP_PORT);
    }
}
