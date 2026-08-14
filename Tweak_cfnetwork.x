// TikTok CFNetwork 底层抓包
// Hook CFReadStream/CFWriteStream 拿到所有网络数据

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>

#define LOG_SERVER @"http://159.75.14.193:8899/log"

static int captureCount = 0;

static void HLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[TKCF] %@", message);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            NSDictionary *log = @{@"message": message, @"timestamp": @([[NSDate date] timeIntervalSince1970])};
            NSData *json = [NSJSONSerialization dataWithJSONObject:log options:0 error:nil];
            if (!json) return;
            NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:LOG_SERVER]];
            req.HTTPMethod = @"POST";
            req.HTTPBody = json;
            [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
            [[[NSURLSession sharedSession] dataTaskWithRequest:req] resume];
        } @catch (__unused NSException *e) {}
    });
}

// ============ Hook NSURLConnection (老式API,但TikTok可能还在用) ============
%hook NSURLConnection
+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error {
    NSString *url = request.URL.absoluteString;
    if ([url rangeOfString:@"profile"].location != NSNotFound || [url rangeOfString:@"user"].location != NSNotFound) {
        HLog(@"[NSURLConnection请求] %@", url);
    }

    NSData *data = %orig;

    if (data && data.length > 100 && ([url rangeOfString:@"profile"].location != NSNotFound || [url rangeOfString:@"user"].location != NSNotFound)) {
        captureCount++;
        HLog(@"[NSURLConnection响应#%d] %lu字节", captureCount, (unsigned long)data.length);

        @try {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (json) {
                NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (jsonStr) {
                    HLog(@"[JSON★#%d] %@", captureCount, [jsonStr substringToIndex:MIN(1500, jsonStr.length)]);
                }
            }
        } @catch (__unused NSException *e) {}
    }

    return data;
}
%end

// ============ Hook NSJSONSerialization (终极兜底) ============
%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    id result = %orig;

    if (result && [result isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)result;

        // 检查是否包含用户字段
        if (dict[@"sec_uid"] || dict[@"unique_id"] || dict[@"follower_count"] || dict[@"following_count"]) {
            captureCount++;
            HLog(@"[JSON解析★#%d] 发现用户数据!", captureCount);

            NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (jsonStr && jsonStr.length > 0) {
                HLog(@"[完整JSON#%d]\n%@", captureCount, [jsonStr substringToIndex:MIN(2000, jsonStr.length)]);

                // 写悬浮窗显示
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIWindow *keyWindow = nil;
                    for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
                        if (window.isKeyWindow) {
                            keyWindow = window;
                            break;
                        }
                    }
                    if (keyWindow) {
                        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, 300, 80)];
                        label.text = [NSString stringWithFormat:@"✅ 抓到用户数据!\n共%d条", captureCount];
                        label.numberOfLines = 0;
                        label.backgroundColor = [[UIColor greenColor] colorWithAlphaComponent:0.8];
                        label.textColor = [UIColor whiteColor];
                        label.layer.cornerRadius = 8;
                        label.clipsToBounds = YES;
                        label.textAlignment = NSTextAlignmentCenter;
                        [keyWindow addSubview:label];

                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                            [label removeFromSuperview];
                        });
                    }
                });
            }
        }
    }

    return result;
}
%end

// ============ 强制关闭 QUIC ============
%hook TTNetworkManagerSettings
- (BOOL)shouldUseQUIC {
    return NO;
}
- (BOOL)enableQUIC {
    return NO;
}
%end

%hook TTHTTPClient
- (BOOL)shouldUseQUIC {
    return NO;
}
%end

// ============ 初始化 ============
%ctor {
    HLog(@"✅ CFNetwork层抓包插件已加载 (含悬浮窗提示)");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        HLog(@"[心跳] 插件运行中, 进程=%@", [[NSProcessInfo processInfo] processName]);

        // 显示加载提示
        UIWindow *keyWindow = nil;
        for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        if (keyWindow) {
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 50, 200, 50)];
            label.text = @"🔍 抓包插件已加载";
            label.backgroundColor = [[UIColor blueColor] colorWithAlphaComponent:0.7];
            label.textColor = [UIColor whiteColor];
            label.textAlignment = NSTextAlignmentCenter;
            label.layer.cornerRadius = 8;
            label.clipsToBounds = YES;
            [keyWindow addSubview:label];

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [label removeFromSuperview];
            });
        }
    });
}
