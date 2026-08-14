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

        // Read x26 memory aggressively - scan large buffer to capture everything
        NSString *raw = nil;
        @try {
            const char *data = (const char *)x26_ptr;
            // Read up to 8KB to ensure complete capture
            raw = [[NSString alloc] initWithBytes:data length:8192 encoding:NSUTF8StringEncoding];
        } @catch (NSException *e) {
            return result;
        }

        if (!raw || [raw rangeOfString:@"x-gorgon"].location == NSNotFound) {
            return result;
        }

        captureCount++;

        // Parse headers and URL from raw data - improved parsing
        NSString *argus = @"", *gorgon = @"", *khronos = @"", *ladon = @"", *query = @"";
        NSString *ttToken = @"", *userAgent = @"";

        // Extract x-argus (format: x-argus=VALUE or x-argus: VALUE or x-argusVALUE)
        NSRange argusRange = [raw rangeOfString:@"x-argus"];
        if (argusRange.location != NSNotFound) {
            NSInteger start = argusRange.location + 7; // skip "x-argus"
            // Skip '=' or ':' and spaces
            while (start < raw.length) {
                unichar ch = [raw characterAtIndex:start];
                if (ch != '=' && ch != ':' && ch != ' ') break;
                start++;
            }
            NSString *sub = [raw substringFromIndex:start];
            // x-argus is at the end, extract until non-base64 char or end
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^([A-Za-z0-9+/=_-]+)" options:0 error:nil];
            NSTextCheckingResult *match = [regex firstMatchInString:sub options:0 range:NSMakeRange(0, MIN(2000, sub.length))];
            if (match) {
                argus = [sub substringWithRange:[match rangeAtIndex:1]];
            }
        }

        // Extract x-tt-token
        NSRange ttTokenRange = [raw rangeOfString:@"x-tt-token"];
        if (ttTokenRange.location != NSNotFound) {
            NSInteger start = ttTokenRange.location + 10; // skip "x-tt-token"
            while (start < raw.length) {
                unichar ch = [raw characterAtIndex:start];
                if (ch != '=' && ch != ':' && ch != ' ') break;
                start++;
            }
            NSString *sub = [raw substringFromIndex:start];
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^([A-Za-z0-9_-]+)" options:0 error:nil];
            NSTextCheckingResult *match = [regex firstMatchInString:sub options:0 range:NSMakeRange(0, MIN(500, sub.length))];
            if (match) {
                ttToken = [sub substringWithRange:[match rangeAtIndex:1]];
            }
        }

        // Extract user-agent
        NSRange uaRange = [raw rangeOfString:@"user-agent" options:NSCaseInsensitiveSearch];
        if (uaRange.location != NSNotFound) {
            NSInteger start = uaRange.location + 10; // skip "user-agent"
            while (start < raw.length) {
                unichar ch = [raw characterAtIndex:start];
                if (ch != '=' && ch != ':' && ch != ' ') break;
                start++;
            }
            NSString *sub = [raw substringFromIndex:start];
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^([^\r\n]+)" options:0 error:nil];
            NSTextCheckingResult *match = [regex firstMatchInString:sub options:0 range:NSMakeRange(0, MIN(500, sub.length))];
            if (match) {
                userAgent = [[sub substringWithRange:[match rangeAtIndex:1]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
        }

        // Extract x-gorgon
        NSRange gorgonRange = [raw rangeOfString:@"x-gorgon"];
        if (gorgonRange.location != NSNotFound) {
            NSInteger start = gorgonRange.location + 8;
            while (start < raw.length) {
                unichar ch = [raw characterAtIndex:start];
                if (ch != '=' && ch != ':' && ch != ' ') break;
                start++;
            }
            NSString *sub = [raw substringFromIndex:start];
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^([0-9a-f]{40,})(?=x-)" options:0 error:nil];
            NSTextCheckingResult *match = [regex firstMatchInString:sub options:0 range:NSMakeRange(0, MIN(100, sub.length))];
            if (match) {
                gorgon = [sub substringWithRange:[match rangeAtIndex:1]];
            }
        }

        // Extract x-khronos
        NSRange khronosRange = [raw rangeOfString:@"x-khronos"];
        if (khronosRange.location != NSNotFound) {
            NSInteger start = khronosRange.location + 9;
            while (start < raw.length) {
                unichar ch = [raw characterAtIndex:start];
                if (ch != '=' && ch != ':' && ch != ' ') break;
                start++;
            }
            NSString *sub = [raw substringFromIndex:start];
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^(\\d{10,})(?=x-)" options:0 error:nil];
            NSTextCheckingResult *match = [regex firstMatchInString:sub options:0 range:NSMakeRange(0, MIN(50, sub.length))];
            if (match) {
                khronos = [sub substringWithRange:[match rangeAtIndex:1]];
            }
        }

        // Extract x-ladon
        NSRange ladonRange = [raw rangeOfString:@"x-ladon"];
        if (ladonRange.location != NSNotFound) {
            NSInteger start = ladonRange.location + 7;
            while (start < raw.length) {
                unichar ch = [raw characterAtIndex:start];
                if (ch != '=' && ch != ':' && ch != ' ') break;
                start++;
            }
            NSString *sub = [raw substringFromIndex:start];
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^([A-Za-z0-9+/=_-]{50,})(?=x-)" options:0 error:nil];
            NSTextCheckingResult *match = [regex firstMatchInString:sub options:0 range:NSMakeRange(0, MIN(1500, sub.length))];
            if (match) {
                ladon = [sub substringWithRange:[match rangeAtIndex:1]];
            }
        }

        // Extract query string
        NSRange musicalRange = [raw rangeOfString:@"musical_ly"];
        if (musicalRange.location != NSNotFound) {
            NSString *qStr = [raw substringFromIndex:musicalRange.location];
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^([a-zA-Z0-9&=_\\-%.]+)" options:0 error:nil];
            NSTextCheckingResult *match = [regex firstMatchInString:qStr options:0 range:NSMakeRange(0, MIN(2000, qStr.length))];
            if (match) {
                query = [qStr substringWithRange:[match rangeAtIndex:1]];
            }
        }

        NSString *fullURL = [NSString stringWithFormat:@"https://api-t.tiktokv.com/tiktok/user/profile/self/v1?%@", query];

        // Store captured data with parsed fields
        NSDictionary *item = @{
            @"id": @(captureCount),
            @"timestamp": [[NSDate date] description],
            @"url": fullURL,
            @"headers": @{
                @"x-argus": argus,
                @"x-gorgon": gorgon,
                @"x-khronos": khronos,
                @"x-ladon": ladon,
                @"x-tt-token": ttToken,
                @"user-agent": userAgent
            },
            @"raw_x26": raw,
            @"raw_length": @(raw.length)
        };

        [capturedData addObject:item];

        // Update floating button
        dispatch_async(dispatch_get_main_queue(), ^{
            if (floatingButton) {
                [floatingButton setTitle:[NSString stringWithFormat:@"📡 %d", captureCount] forState:UIControlStateNormal];
            }
        });

        NSLog(@"[TikTokHeaders] Captured #%d, raw length: %lu", captureCount, (unsigned long)raw.length);
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
        [html appendFormat:@"<div class='header'><span class='label'>x-tt-token:</span> %@</div>", headers[@"x-tt-token"]];
        [html appendFormat:@"<div class='header'><span class='label'>user-agent:</span> %@</div>", headers[@"user-agent"]];

        NSString *ladon = headers[@"x-ladon"];
        if (ladon.length > 100) {
            [html appendFormat:@"<div class='header'><span class='label'>x-ladon:</span> %@...</div>", [ladon substringToIndex:100]];
        } else {
            [html appendFormat:@"<div class='header'><span class='label'>x-ladon:</span> %@</div>", ladon];
        }

        // Show raw dump in details tag
        NSString *rawData = item[@"raw_x26"];
        if (rawData) {
            [html appendString:@"<details style='margin-top:10px'><summary style='cursor:pointer;color:#ff0'>Show Raw x26 Dump</summary>"];
            [html appendFormat:@"<pre style='color:#0f0;font-size:9px;white-space:pre-wrap;word-break:break-all;margin-top:5px'>%@</pre>", rawData];
            [html appendString:@"</details>"];
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
        [text appendFormat:@"x-tt-token: %@\n", h[@"x-tt-token"]];
        [text appendFormat:@"user-agent: %@\n", h[@"user-agent"]];
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
        // Find or create top-level window
        UIWindow *targetWindow = nil;
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.windowLevel == UIWindowLevelNormal && window.isKeyWindow) {
                targetWindow = window;
                break;
            }
        }
        if (!targetWindow) {
            for (UIWindow *window in [UIApplication sharedApplication].windows) {
                if (window.windowLevel == UIWindowLevelNormal) {
                    targetWindow = window;
                    break;
                }
            }
        }
        if (!targetWindow) return;

        floatingButton = [UIButton buttonWithType:UIButtonTypeSystem];
        floatingButton.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 80, 100, 70, 40);
        floatingButton.backgroundColor = [UIColor colorWithRed:0 green:0.8 blue:0 alpha:0.9];
        floatingButton.layer.cornerRadius = 20;
        floatingButton.layer.zPosition = 9999; // Force to front
        [floatingButton setTitle:[NSString stringWithFormat:@"📡 %d", captureCount] forState:UIControlStateNormal];
        [floatingButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        [floatingButton addTarget:nil action:@selector(showDataWindow) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:@selector(handlePan:)];
        [floatingButton addGestureRecognizer:pan];

        [targetWindow addSubview:floatingButton];

        NSLog(@"[TikTokHeaders] Floating button created on window: %@", targetWindow);

        // Keep updating button every 2 seconds to ensure visibility
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            while (YES) {
                sleep(2);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (floatingButton && floatingButton.superview) {
                        [floatingButton setTitle:[NSString stringWithFormat:@"📡 %d", captureCount] forState:UIControlStateNormal];
                        [floatingButton.superview bringSubviewToFront:floatingButton];
                    }
                });
            }
        });
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
