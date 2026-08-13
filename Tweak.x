// TikTok个人中心网络请求抓包插件
// 作者: 海鸥
// 功能: 拦截个人中心API请求，保存完整的请求/响应数据

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define HLog(fmt, ...) NSLog(@"[TikTokDump] " fmt, ##__VA_ARGS__)

// 保存路径
static NSString *dumpPath = @"/var/mobile/Documents/TikTokDump/";

// 创建dump目录
%ctor {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dumpPath]) {
        [fm createDirectoryAtPath:dumpPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    HLog(@"========================================");
    HLog(@"TikTok网络请求Dump插件已加载");
    HLog(@"保存路径: %@", dumpPath);
    HLog(@"========================================");
}

// 保存数据到文件
static void saveDumpData(NSString *filename, NSString *content) {
    NSString *filePath = [dumpPath stringByAppendingPathComponent:filename];
    NSError *error = nil;
    [content writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        HLog(@"保存失败: %@", error);
    } else {
        HLog(@"已保存: %@", filename);
    }
}

// ============================================
// Hook NSURLSession
// ============================================
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    
    NSString *urlString = request.URL.absoluteString;
    
    // 只拦截个人中心相关的API
    if ([urlString containsString:@"/aweme/v1/user/profile"] || 
        [urlString containsString:@"/aweme/v1/user"] ||
        [urlString containsString:@"profile"] ||
        [urlString containsString:@"user"]) {
        
        HLog(@"========================================");
        HLog(@"拦截到个人中心请求!");
        HLog(@"URL: %@", urlString);
        
        // 保存请求信息
        NSMutableString *requestInfo = [NSMutableString string];
        [requestInfo appendFormat:@"=== 请求时间 ===\n%@\n\n", [NSDate date]];
        [requestInfo appendFormat:@"=== 请求URL ===\n%@\n\n", urlString];
        [requestInfo appendFormat:@"=== 请求方法 ===\n%@\n\n", request.HTTPMethod ?: @"GET"];
        
        // 保存请求头
        [requestInfo appendString:@"=== 请求头 ===\n"];
        [request.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
            [requestInfo appendFormat:@"%@: %@\n", key, value];
        }];
        [requestInfo appendString:@"\n"];
        
        // 保存请求体
        if (request.HTTPBody) {
            NSString *bodyString = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
            [requestInfo appendFormat:@"=== 请求体 ===\n%@\n\n", bodyString ?: @"(二进制数据)"];
        }
        
        // 生成文件名
        NSString *timestamp = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
        NSString *requestFilename = [NSString stringWithFormat:@"request_%@.txt", timestamp];
        saveDumpData(requestFilename, requestInfo);
        
        // Hook completionHandler
        void (^newHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            if (data && response) {
                HLog(@"收到响应，大小: %lu bytes", (unsigned long)data.length);
                
                NSMutableString *responseInfo = [NSMutableString string];
                [responseInfo appendFormat:@"=== 响应时间 ===\n%@\n\n", [NSDate date]];
                [responseInfo appendFormat:@"=== 响应URL ===\n%@\n\n", response.URL.absoluteString];
                
                // 保存响应头
                if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                    [responseInfo appendFormat:@"=== 状态码 ===\n%ld\n\n", (long)httpResponse.statusCode];
                    [responseInfo appendString:@"=== 响应头 ===\n"];
                    [httpResponse.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
                        [responseInfo appendFormat:@"%@: %@\n", key, value];
                    }];
                    [responseInfo appendString:@"\n"];
                }
                
                // 保存响应体
                NSString *responseBody = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (responseBody) {
                    [responseInfo appendFormat:@"=== 响应体 ===\n%@\n", responseBody];
                    
                    // 如果是JSON，格式化后也保存一份
                    NSError *jsonError = nil;
                    id jsonObj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                    if (jsonObj && !jsonError) {
                        NSData *prettyData = [NSJSONSerialization dataWithJSONObject:jsonObj options:NSJSONWritingPrettyPrinted error:nil];
                        NSString *prettyJSON = [[NSString alloc] initWithData:prettyData encoding:NSUTF8StringEncoding];
                        NSString *jsonFilename = [NSString stringWithFormat:@"response_%@.json", timestamp];
                        saveDumpData(jsonFilename, prettyJSON);
                    }
                } else {
                    [responseInfo appendFormat:@"=== 响应体 ===\n(二进制数据，大小: %lu bytes)\n", (unsigned long)data.length];
                }
                
                NSString *responseFilename = [NSString stringWithFormat:@"response_%@.txt", timestamp];
                saveDumpData(responseFilename, responseInfo);
            }
            
            // 调用原始回调
            if (completionHandler) {
                completionHandler(data, response, error);
            }
        };
        
        return %orig(request, newHandler);
    }
    
    return %orig;
}

%end

// ============================================
// Hook NSURLConnection (老版API)
// ============================================
%hook NSURLConnection

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error {
    NSString *urlString = request.URL.absoluteString;
    
    if ([urlString containsString:@"profile"] || [urlString containsString:@"user"]) {
        HLog(@"拦截到同步请求: %@", urlString);
        // 这里可以加类似的dump逻辑
    }
    
    return %orig;
}

%end

// ============================================
// Hook AWEProfileHeaderMyProfileViewController
// ============================================
%hook AWEProfileHeaderMyProfileViewController

- (void)viewDidAppear:(BOOL)animated {
    HLog(@"========================================");
    HLog(@"进入个人中心页面，开始监控网络请求...");
    HLog(@"========================================");
    %orig;
}

%end
