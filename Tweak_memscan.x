// TikTok 内存扫描 - 直接从进程内存里找用户数据
// 原理: 每秒扫描所有可读内存区域，查找包含 sec_uid/follower_count 的 JSON

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <mach/vm_region.h>
#import <mach/vm_map.h>

#define LOG_SERVER @"http://159.75.14.193:8899/log"

static int g_found_count = 0;
static NSMutableSet *g_found_hashes = nil; // 去重

static void HLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[TKMemScan] %@", message);

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

// 扫描当前进程的所有内存区域
static void scanMemoryForUserData() {
    @autoreleasepool {
        mach_port_t task = mach_task_self();
        vm_address_t address = 0;
        vm_size_t size = 0;

        while (1) {
            mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
            vm_region_basic_info_data_64_t info;
            mach_port_t object_name = MACH_PORT_NULL;

            kern_return_t kr = vm_region_64(task, &address, &size, VM_REGION_BASIC_INFO_64,
                                           (vm_region_info_t)&info, &count, &object_name);

            if (kr != KERN_SUCCESS) break;

            // 只扫描可读的内存区域
            if ((info.protection & VM_PROT_READ) && size > 100 && size < 100*1024*1024) {
                @try {
                    // 读取内存
                    vm_offset_t data = 0;
                    mach_msg_type_number_t data_count = 0;
                    kr = vm_read(task, address, size, &data, &data_count);

                    if (kr == KERN_SUCCESS && data && data_count > 100) {
                        NSData *memData = [NSData dataWithBytesNoCopy:(void*)data length:data_count freeWhenDone:NO];
                        NSString *memStr = [[NSString alloc] initWithData:memData encoding:NSUTF8StringEncoding];

                        if (memStr && memStr.length > 50) {
                            // 查找关键字段
                            if ([memStr rangeOfString:@"sec_uid"].location != NSNotFound ||
                                [memStr rangeOfString:@"follower_count"].location != NSNotFound ||
                                [memStr rangeOfString:@"unique_id"].location != NSNotFound) {

                                // 尝试提取 JSON 片段
                                NSRange start = [memStr rangeOfString:@"{"];
                                if (start.location != NSNotFound && start.location < memStr.length - 100) {
                                    NSString *jsonCandidate = [memStr substringFromIndex:start.location];
                                    NSRange end = [jsonCandidate rangeOfString:@"}" options:NSBackwardsSearch];

                                    if (end.location != NSNotFound && end.location < MIN(5000, jsonCandidate.length)) {
                                        jsonCandidate = [jsonCandidate substringToIndex:end.location + 1];

                                        // 去重
                                        NSString *hash = [NSString stringWithFormat:@"%lu", (unsigned long)[jsonCandidate hash]];
                                        if (![g_found_hashes containsObject:hash]) {
                                            [g_found_hashes addObject:hash];

                                            // 验证是否是有效 JSON
                                            NSData *jsonData = [jsonCandidate dataUsingEncoding:NSUTF8StringEncoding];
                                            id parsed = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];

                                            if (parsed && [parsed isKindOfClass:[NSDictionary class]]) {
                                                NSDictionary *dict = (NSDictionary*)parsed;
                                                if (dict[@"sec_uid"] || dict[@"follower_count"] || dict[@"unique_id"]) {
                                                    g_found_count++;
                                                    HLog(@"[内存扫描★#%d] 找到用户数据! 地址=0x%lx", g_found_count, (unsigned long)address);
                                                    HLog(@"[JSON] %@", jsonCandidate.length > 2000 ? [jsonCandidate substringToIndex:2000] : jsonCandidate);

                                                    // 悬浮窗提示
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
                                                            label.text = [NSString stringWithFormat:@"✅ 内存扫到数据!\n共%d条", g_found_count];
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
                                    }
                                }
                            }
                        }

                        vm_deallocate(task, data, data_count);
                    }
                } @catch (__unused NSException *e) {}
            }

            address += size;
        }
    }
}

%ctor {
    g_found_hashes = [NSMutableSet set];
    HLog(@"✅ 内存扫描插件已加载");

    // 延迟 5 秒启动扫描，避免启动时崩溃
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        HLog(@"[开始扫描] 每 3 秒扫描一次内存...");

        // 每 3 秒扫描一次
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                         dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer, ^{
            scanMemoryForUserData();
        });
        dispatch_resume(timer);
    });

    // 启动提示
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        if (keyWindow) {
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 50, 250, 50)];
            label.text = @"🔍 内存扫描已启动";
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
