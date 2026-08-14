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
static NSMutableArray *debugLogs = nil;
static CFSocketRef serverSocket = NULL;
static int captureCount = 0;
static UIButton *floatingButton = nil;
static UIWindow *dataWindow = nil;

// Helper to add debug log
static void addDebugLog(NSString *message) {
    if (!debugLogs) {
        debugLogs = [NSMutableArray new];
    }
    NSString *timestamp = [[NSDate date] description];
    [debugLogs addObject:[NSString stringWithFormat:@"[%@] %@", timestamp, message]];
    NSLog(@"[TikTokHeaders] %@", message);
}

// ==================== memcmp Hook ====================

// Original memcmp
static int (*original_memcmp)(const void *, const void *, size_t);
static int (*original_bcmp)(const void *, const void *, size_t);
static int (*original_strcmp)(const char *, const char *);

// Enhanced header extraction - handles both key:value and keyvalue formats
static NSString* extractHeader(NSString *raw, NSString *key) {
    NSRange keyRange = [raw rangeOfString:key options:NSCaseInsensitiveSearch];
    if (keyRange.location == NSNotFound) return @"";

    NSInteger start = keyRange.location + key.length;
    if (start >= raw.length) return @"";

    // Skip separators: '=', ':', ' ', '\r', '\n'
    while (start < raw.length) {
        unichar ch = [raw characterAtIndex:start];
        if (ch != '=' && ch != ':' && ch != ' ' && ch != '\r' && ch != '\n') break;
        start++;
    }

    if (start >= raw.length) return @"";

    // Find end - stop at next header key or control chars
    NSInteger end = start;
    NSArray *stopMarkers = @[@"x-argus", @"x-gorgon", @"x-khronos", @"x-ladon", @"x-tt-token",
                              @"user-agent", @"cookie", @"x-tt-pba-encode", @"x-vc-bdturing-sdk-version",
                              @"passport-sdk-version", @"pns-att-enable", @"oec-vc-sdk-version",
                              @"x-tt-request-tag", @"rpc-persist-pns-region-1", @"x-tt-store-region",
                              @"x-tt-store-region-src", @"rpc-persist-pyxis-policy-v-tnc", @"x-ss-dp",
                              @"x-tt-trace-id", @"accept-encoding"];

    NSInteger minEnd = raw.length;
    for (NSString *marker in stopMarkers) {
        NSRange markerRange = [raw rangeOfString:marker options:NSCaseInsensitiveSearch range:NSMakeRange(start, raw.length - start)];
        if (markerRange.location != NSNotFound && markerRange.location < minEnd) {
            minEnd = markerRange.location;
        }
    }

    // Also check for \r\n\r\n (end of headers)
    NSRange doubleNewline = [raw rangeOfString:@"\r\n\r\n" options:0 range:NSMakeRange(start, raw.length - start)];
    if (doubleNewline.location != NSNotFound && doubleNewline.location < minEnd) {
        minEnd = doubleNewline.location;
    }

    end = minEnd;

    if (end <= start) return @"";

    NSString *value = [[raw substringWithRange:NSMakeRange(start, end - start)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return value;
}

// Hooked bcmp - additional hook for A10 compatibility
static int hooked_bcmp(const void *s1, const void *s2, size_t n) {
    int result = original_bcmp(s1, s2, n);

    if (result != 0 || n != 8) return result;

    @autoreleasepool {
        char str1[9] = {0}, str2[9] = {0};
        memcpy(str1, s1, 8);
        memcpy(str2, s2, 8);

        if (strcmp(str1, "x-gorgon") != 0 && strcmp(str2, "x-gorgon") != 0) {
            return result;
        }

        addDebugLog(@"bcmp hit x-gorgon!");

        // Call memcmp handler to avoid code duplication
        return hooked_memcmp(s1, s2, n);
    }
}

// Hooked strcmp - additional hook for A10 compatibility
static int hooked_strcmp(const char *s1, const char *s2) {
    int result = original_strcmp(s1, s2);

    if (result != 0) return result;

    @autoreleasepool {
        if (strcmp(s1, "x-gorgon") == 0 || strcmp(s2, "x-gorgon") == 0) {
            addDebugLog(@"strcmp hit x-gorgon!");
        }
    }

    return result;
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

        addDebugLog(@"memcmp hit x-gorgon!");

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

        // Extract all headers using improved extraction
        NSString *argus = extractHeader(raw, @"x-argus");
        NSString *gorgon = extractHeader(raw, @"x-gorgon");
        NSString *khronos = extractHeader(raw, @"x-khronos");
        NSString *ladon = extractHeader(raw, @"x-ladon");
        NSString *ttToken = extractHeader(raw, @"x-tt-token");
        NSString *userAgent = extractHeader(raw, @"user-agent");
        NSString *cookie = extractHeader(raw, @"cookie");
        NSString *ttPbaEncode = extractHeader(raw, @"x-tt-pba-encode");
        NSString *vcBdturingSdkVersion = extractHeader(raw, @"x-vc-bdturing-sdk-version");
        NSString *passportSdkVersion = extractHeader(raw, @"passport-sdk-version");
        NSString *pnsAttEnable = extractHeader(raw, @"pns-att-enable");
        NSString *oecVcSdkVersion = extractHeader(raw, @"oec-vc-sdk-version");
        NSString *ttRequestTag = extractHeader(raw, @"x-tt-request-tag");
        NSString *rpcPersistPnsRegion1 = extractHeader(raw, @"rpc-persist-pns-region-1");
        NSString *ttStoreRegion = extractHeader(raw, @"x-tt-store-region");
        NSString *ttStoreRegionSrc = extractHeader(raw, @"x-tt-store-region-src");
        NSString *rpcPersistPyxisPolicyVTnc = extractHeader(raw, @"rpc-persist-pyxis-policy-v-tnc");
        NSString *ssDp = extractHeader(raw, @"x-ss-dp");
        NSString *ttTraceId = extractHeader(raw, @"x-tt-trace-id");
        NSString *acceptEncoding = extractHeader(raw, @"accept-encoding");

        // Extract query string - try multiple patterns
        NSString *query = @"";

        // Pattern 1: Look for common API paths
        NSArray *apiPaths = @[@"musical_ly", @"api-t.tiktokv.com", @"api22-normal", @"tiktok/v1"];
        for (NSString *path in apiPaths) {
            NSRange pathRange = [raw rangeOfString:path];
            if (pathRange.location != NSNotFound) {
                NSString *qStr = [raw substringFromIndex:pathRange.location];
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^([a-zA-Z0-9&=_\\-%.?/]+)" options:0 error:nil];
                NSTextCheckingResult *match = [regex firstMatchInString:qStr options:0 range:NSMakeRange(0, MIN(3000, qStr.length))];
                if (match) {
                    query = [qStr substringWithRange:[match rangeAtIndex:1]];
                    break;
                }
            }
        }

        // Try to extract full URL if possible
        NSString *fullURL = @"";
        if (query.length > 0) {
            if ([query containsString:@"://"]) {
                fullURL = query; // Already a full URL
            } else if ([query hasPrefix:@"/"]) {
                fullURL = [NSString stringWithFormat:@"https://api-t.tiktokv.com%@", query];
            } else {
                fullURL = [NSString stringWithFormat:@"https://api-t.tiktokv.com/?%@", query];
            }
        }

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
                @"user-agent": userAgent,
                @"cookie": cookie,
                @"x-tt-pba-encode": ttPbaEncode,
                @"x-vc-bdturing-sdk-version": vcBdturingSdkVersion,
                @"passport-sdk-version": passportSdkVersion,
                @"pns-att-enable": pnsAttEnable,
                @"oec-vc-sdk-version": oecVcSdkVersion,
                @"x-tt-request-tag": ttRequestTag,
                @"rpc-persist-pns-region-1": rpcPersistPnsRegion1,
                @"x-tt-store-region": ttStoreRegion,
                @"x-tt-store-region-src": ttStoreRegionSrc,
                @"rpc-persist-pyxis-policy-v-tnc": rpcPersistPyxisPolicyVTnc,
                @"x-ss-dp": ssDp,
                @"x-tt-trace-id": ttTraceId,
                @"accept-encoding": acceptEncoding
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
    [html appendString:@".logs{border:2px solid #f00;margin:20px 0;padding:15px;background:#220000}"];
    [html appendString:@".log{color:#fff;margin:3px 0;font-size:11px}"];
    [html appendString:@"h1{color:#0ff}h2{color:#f00}</style></head><body>"];
    [html appendFormat:@"<h1>TikTok Request Headers</h1><p>Captured: %d</p>", (int)capturedData.count];

    // Add debug logs section at top
    if (debugLogs && debugLogs.count > 0) {
        [html appendString:@"<div class='logs'><h2>🔍 Debug Logs (最近20条)</h2>"];
        NSArray *recentLogs = debugLogs.count > 20 ? [debugLogs subarrayWithRange:NSMakeRange(debugLogs.count - 20, 20)] : debugLogs;
        for (NSString *log in [recentLogs reverseObjectEnumerator]) {
            [html appendFormat:@"<div class='log'>%@</div>", log];
        }
        [html appendString:@"</div>"];
    } else {
        [html appendString:@"<div class='logs'><h2>🔍 Debug Logs</h2><p style='color:#888'>No logs yet. dylib可能没加载或hook未触发。</p></div>"];
    }

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
        [html appendFormat:@"<div class='header'><span class='label'>x-tt-pba-encode:</span> %@</div>", headers[@"x-tt-pba-encode"]];
        [html appendFormat:@"<div class='header'><span class='label'>x-vc-bdturing-sdk-version:</span> %@</div>", headers[@"x-vc-bdturing-sdk-version"]];
        [html appendFormat:@"<div class='header'><span class='label'>passport-sdk-version:</span> %@</div>", headers[@"passport-sdk-version"]];
        [html appendFormat:@"<div class='header'><span class='label'>pns-att-enable:</span> %@</div>", headers[@"pns-att-enable"]];
        [html appendFormat:@"<div class='header'><span class='label'>oec-vc-sdk-version:</span> %@</div>", headers[@"oec-vc-sdk-version"]];
        [html appendFormat:@"<div class='header'><span class='label'>x-tt-request-tag:</span> %@</div>", headers[@"x-tt-request-tag"]];
        [html appendFormat:@"<div class='header'><span class='label'>rpc-persist-pns-region-1:</span> %@</div>", headers[@"rpc-persist-pns-region-1"]];
        [html appendFormat:@"<div class='header'><span class='label'>x-tt-store-region:</span> %@</div>", headers[@"x-tt-store-region"]];
        [html appendFormat:@"<div class='header'><span class='label'>x-tt-store-region-src:</span> %@</div>", headers[@"x-tt-store-region-src"]];
        [html appendFormat:@"<div class='header'><span class='label'>rpc-persist-pyxis-policy-v-tnc:</span> %@</div>", headers[@"rpc-persist-pyxis-policy-v-tnc"]];
        [html appendFormat:@"<div class='header'><span class='label'>x-ss-dp:</span> %@</div>", headers[@"x-ss-dp"]];
        [html appendFormat:@"<div class='header'><span class='label'>x-tt-trace-id:</span> %@</div>", headers[@"x-tt-trace-id"]];
        [html appendFormat:@"<div class='header'><span class='label'>accept-encoding:</span> %@</div>", headers[@"accept-encoding"]];

        NSString *ladon = headers[@"x-ladon"];
        if (ladon.length > 100) {
            [html appendFormat:@"<div class='header'><span class='label'>x-ladon:</span> %@...</div>", [ladon substringToIndex:100]];
        } else {
            [html appendFormat:@"<div class='header'><span class='label'>x-ladon:</span> %@</div>", ladon];
        }

        NSString *cookie = headers[@"cookie"];
        if (cookie.length > 100) {
            [html appendFormat:@"<div class='header'><span class='label'>cookie:</span> %@...</div>", [cookie substringToIndex:100]];
        } else {
            [html appendFormat:@"<div class='header'><span class='label'>cookie:</span> %@</div>", cookie];
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
        debugLogs = [NSMutableArray new];

        addDebugLog(@"dylib loaded - multi-hook mode for A10 compatibility");

        // Hook memcmp
        MSHookFunction((void *)memcmp, (void *)hooked_memcmp, (void **)&original_memcmp);
        addDebugLog(@"memcmp hooked");

        // Hook bcmp for A10 compatibility
        MSHookFunction((void *)bcmp, (void *)hooked_bcmp, (void **)&original_bcmp);
        addDebugLog(@"bcmp hooked");

        // Hook strcmp for debugging
        MSHookFunction((void *)strcmp, (void *)hooked_strcmp, (void **)&original_strcmp);
        addDebugLog(@"strcmp hooked");

        // Start HTTP server
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            startHTTPServer();
            addDebugLog(@"HTTP server started on port 8888");
        });

        // Create floating button
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            createFloatingButton();
            addDebugLog(@"Floating button created");
        });

        NSLog(@"[TikTokHeaders] HTTP Server on port %d, access via http://192.168.9.102:8888", HTTP_PORT);
    }
}
