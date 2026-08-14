#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define HTTP_PORT 9999
#define LOG_SERVER_URL @"http://159.75.14.193:8899/log"

static NSMutableArray *capturedData = nil;
static GCDWebServer *webServer = nil;
static int captureCount = 0;

// ==================== HTTP 本地服务 ====================

%hook AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL result = %orig;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self setupLocalServer];
    });

    return result;
}

%new
- (void)setupLocalServer {
    if (webServer) return;

    capturedData = [NSMutableArray new];

    Class GCDWebServerClass = NSClassFromString(@"GCDWebServer");
    if (!GCDWebServerClass) {
        NSLog(@"[TKCapture] GCDWebServer not found, trying dynamic load");
        return;
    }

    webServer = [[GCDWebServerClass alloc] init];

    // GET / - 主页
    [webServer addDefaultHandlerForMethod:@"GET"
        requestClass:NSClassFromString(@"GCDWebServerRequest")
        processBlock:^GCDWebServerResponse *(id request) {
            NSString *html = [NSString stringWithFormat:@
                "<html><head><meta charset='utf-8'><title>TikTok Capture</title>"
                "<style>body{font-family:monospace;padding:20px;background:#1a1a1a;color:#0f0}"
                ".item{border:1px solid #0f0;margin:10px 0;padding:10px;background:#000}"
                ".url{color:#0ff;word-break:break-all}"
                ".json{color:#ff0;white-space:pre-wrap;max-height:300px;overflow:auto}"
                "</style></head><body>"
                "<h1>TikTok Profile Capture</h1>"
                "<p>捕获数量: %d</p>"
                "<div id='list'>%@</div>"
                "<script>setInterval(()=>location.reload(),5000)</script>"
                "</body></html>",
                (int)capturedData.count,
                [self formatCapturedData]
            ];

            return [NSClassFromString(@"GCDWebServerDataResponse")
                responseWithHTML:html];
        }];

    // GET /api/data - JSON API
    [webServer addDefaultHandlerForMethod:@"GET"
        requestClass:NSClassFromString(@"GCDWebServerRequest")
        processBlock:^GCDWebServerResponse *(id request) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:capturedData
                options:NSJSONWritingPrettyPrinted error:nil];

            return [NSClassFromString(@"GCDWebServerDataResponse")
                responseWithData:jsonData contentType:@"application/json"];
        }];

    NSError *error = nil;
    [webServer startWithPort:HTTP_PORT bonjourName:nil];

    if (error) {
        NSLog(@"[TKCapture] Server failed: %@", error);
    } else {
        NSLog(@"[TKCapture] ✓ Server running on http://localhost:%d", HTTP_PORT);
    }
}

%new
- (NSString *)formatCapturedData {
    NSMutableString *html = [NSMutableString new];

    for (NSDictionary *item in [capturedData reverseObjectEnumerator]) {
        [html appendFormat:@"<div class='item'>"
            "<b>ID:</b> %@<br>"
            "<b>URL:</b> <span class='url'>%@</span><br>"
            "<b>响应:</b><pre class='json'>%@</pre>"
            "</div>",
            item[@"id"],
            item[@"url"],
            item[@"response"]
        ];
    }

    return html.length > 0 ? html : @"<p>暂无数据</p>";
}

%end

// ==================== Hook NSJSONSerialization ====================

%hook NSJSONSerialization

+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    id result = %orig;

    if (result && data.length > 1000 && data.length < 100000) {
        @try {
            NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

            // 只抓 profile/self 相关的 JSON
            if (jsonStr && [jsonStr containsString:@"author_stats"]) {
                captureCount++;

                NSMutableDictionary *capture = [NSMutableDictionary new];
                capture[@"id"] = @(captureCount);
                capture[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
                capture[@"type"] = @"response";
                capture[@"url"] = @"profile/self";
                capture[@"response"] = jsonStr;

                [capturedData addObject:capture];

                // 上报到远程服务器
                [self uploadToServer:capture];

                NSLog(@"[TKCapture] ★★★ Captured #%d (size: %lu)",
                    captureCount, (unsigned long)data.length);
            }
        } @catch (NSException *e) {
            // ignore
        }
    }

    return result;
}

%new
+ (void)uploadToServer:(NSDictionary *)data {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            NSURL *url = [NSURL URLWithString:LOG_SERVER_URL];
            NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
            req.HTTPMethod = @"POST";
            [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

            req.HTTPBody = [NSJSONSerialization dataWithJSONObject:data options:0 error:nil];

            [[[NSURLSession sharedSession] dataTaskWithRequest:req] resume];
        } @catch (NSException *e) {
            // ignore
        }
    });
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

%ctor {
    NSLog(@"[TKCapture] ✓ Loaded");

    capturedData = [NSMutableArray new];
}
