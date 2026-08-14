// TikTok 强制 HTTPS + 抓明文响应
// 功能: 1. 禁用 QUIC 强制走 HTTPS  2. Hook NSURLSession 拿明文 JSON

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define LOG_SERVER @"http://159.75.14.193:8899/log"

static void HLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[TKSimple] %@", message);

    // 远程日志
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

// ============ 1. 强制关闭 QUIC ============
%hook TTNetworkManagerSettings
- (BOOL)shouldUseQUIC {
    HLog(@"[QUIC] 拦截 shouldUseQUIC -> 返回 NO");
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

// ============ 2. Hook NSURLSession 抓明文响应 ============
%hook NSURLSessionDataTask
- (void)resume {
    NSURLRequest *request = [self currentRequest];
    if (!request) {
        %orig;
        return;
    }

    NSString *urlString = request.URL.absoluteString;

    // 只关注 profile/self 或 user/profile 接口
    if ([urlString rangeOfString:@"profile/self"].location == NSNotFound &&
        [urlString rangeOfString:@"user/profile"].location == NSNotFound) {
        %orig;
        return;
    }

    HLog(@"[请求] %@", urlString);
    %orig;
}
%end

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                             completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {

    NSString *urlString = request.URL.absoluteString;

    // 只 hook profile 相关接口
    if ([urlString rangeOfString:@"profile/self"].location == NSNotFound &&
        [urlString rangeOfString:@"user/profile"].location == NSNotFound) {
        return %orig;
    }

    HLog(@"[Hook] NSURLSession profile 请求: %@", urlString);

    // 包装原始回调
    void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && data.length > 0) {
            HLog(@"[响应★] 收到数据 %lu 字节", (unsigned long)data.length);

            // 尝试解析 JSON
            @try {
                id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (json) {
                    NSString *jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (jsonString) {
                        HLog(@"[JSON★] %@", [jsonString substringToIndex:MIN(2000, jsonString.length)]);

                        // 保存到沙盒
                        NSString *docPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
                        NSString *filePath = [docPath stringByAppendingPathComponent:@"tiktok_profile.json"];
                        [data writeToFile:filePath atomically:YES];
                        HLog(@"[保存] %@", filePath);
                    }
                }
            } @catch (__unused NSException *e) {}
        }

        // 调用原始回调
        if (completionHandler) {
            completionHandler(data, response, error);
        }
    };

    return %orig(request, wrappedHandler);
}
%end

// ============ 初始化 ============
%ctor {
    HLog(@"✅ TikTok 简化抓包插件已加载 (强制HTTPS + NSURLSession hook)");

    // 立即测试日志是否能发出去
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        HLog(@"[心跳] dylib 运行中...");
    });

    // 打印当前进程名，确认注入到 TikTok
    NSString *processName = [[NSProcessInfo processInfo] processName];
    HLog(@"[进程] %@", processName);
}
