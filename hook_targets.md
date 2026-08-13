# TikTok Hook目标清单

## 立即可用的Hook点

### 1. BDTuring风控绕过（优先级：最高）

类：BDTuringSparkManager
位置：MusicallyCore.framework
作用：风控验证总调度

核心方法：
- verifyWithCompletion: - 验证回调，返回验证结果
- loadSettings:completion: - 加载风控配置
- twiceVerifyWithParams:completion: - 二次验证

### 2. 网络可达性强制放行（优先级：高）

类：NetworkReachabilityManager
作用：控制App认为网络是否可用

关键方法：
- isReachable - 返回网络是否可达
- isReachableViaWWAN - 返回蜂窝网络是否可达
- isReachableViaWiFi - 返回WiFi是否可达
- currentReachabilityStatus - 返回当前网络状态（0=不可达,1=蜂窝,2=WiFi）

### 3. 设备指纹替换（优先级：高）

关键类：
- AWEClientDeviceIDKeychainWrapper - Keychain存储的设备ID
- TIMDeviceIDProvider - 设备ID提供者
- GECPigeonDeviceIDProvider - 另一个设备ID提供者
- NSUserDefaults - UserDefaults存储的设备ID

关键Key：
- kDeviceIDStorageKey
- kInstallIDStorageKey
- AWEClientDeviceIDKeychainKey

### 4. TTHttpTask网络请求拦截（优先级：中）

类：TTHttpTask
作用：所有HTTP网络请求的执行者

关键方法：
- resume - 开始执行请求
- didCompleteWithError: - 请求完成回调

### 5. TTNetworkManager错误处理（优先级：中）

类：TTNetworkManager
作用：网络管理器，处理请求错误

关键方法：
- handleNetworkError: - 处理网络错误
- requestDidFailWithError:task: - 请求失败处理

### 6. AAWEBootChecker启动检测（优先级：中）

类：AAWEBootChecker
作用：App启动时的安全检测

关键方法：
- load - 类加载时执行
- shouldCheckTargetPath: - 是否检查指定路径

### 7. SecuritySDK初始化（优先级：低）

类：
- GBLSecuritySDKServiceImpl - 安全SDK服务实现
- TTSecurityPluginAdapterImpl - 安全插件适配器

---

## 完整Tweak示例（theos）

### Tweak.x
```objc
#import <Foundation/Foundation.h>

%hook BDTuringSparkManager
- (void)verifyWithCompletion:(void (^)(id))completion {
    id result = [[objc_getClass("BDTuringVerifyResult") alloc] init];
    [result setValue:@YES forKey:@"isSuccess"];
    completion(result);
}
%end

%hook NetworkReachabilityManager
- (BOOL)isReachable { return YES; }
- (int)currentReachabilityStatus { return 2; }
%end

%hook NSUserDefaults
- (id)objectForKey:(NSString *)key {
    if ([key containsString:@"DeviceID"]) {
        return @"CLEAN_DEVICE_ID_HERE";
    }
    return %orig;
}
%end

%hook TTNetworkManager
- (void)handleNetworkError:(NSError *)error {
    NSLog(@"[Bypass] Suppressed: %@", error);
}
%end

%ctor {
    NSLog(@"[TikTokBypass] Loaded");
}
```

---

## Frida诊断脚本

```javascript
// 运行: frida -U -f com.zhiliaoapp.musically -l diagnose.js

console.log("[*] TikTok Diagnostic Started");

// Hook BDTuring
if (ObjC.classes.BDTuringSparkManager) {
    var cls = ObjC.classes.BDTuringSparkManager;
    Interceptor.attach(cls["- verifyWithCompletion:"].implementation, {
        onEnter: function(args) {
            console.log("[BDTuring] Verify called");
        }
    });
}

// Hook Network
if (ObjC.classes.NetworkReachabilityManager) {
    var cls = ObjC.classes.NetworkReachabilityManager;
    Interceptor.attach(cls["- isReachable"].implementation, {
        onLeave: function(ret) {
            console.log("[Network] isReachable:", ret);
        }
    });
}

// Hook HTTP
if (ObjC.classes.TTHttpTask) {
    var cls = ObjC.classes.TTHttpTask;
    Interceptor.attach(cls["- resume"].implementation, {
        onEnter: function(args) {
            var self = new ObjC.Object(args[0]);
            try {
                var req = self.$ivars['_request'];
                if (req) {
                    console.log("[HTTP] URL:", req.URL().toString());
                    console.log("[HTTP] Headers:", req.allHTTPHeaderFields());
                }
            } catch(e) {}
        }
    });
}

console.log("[*] Hooks installed");
```

---

## 关键类总结

| 类名 | 方法 | 作用 | 优先级 |
|------|------|------|--------|
| BDTuringSparkManager | verifyWithCompletion: | 风控验证 | 最高 |
| NetworkReachabilityManager | isReachable | 网络检测 | 高 |
| NSUserDefaults | objectForKey: | 设备ID | 高 |
| TTHttpTask | resume | HTTP请求 | 中 |
| TTNetworkManager | handleNetworkError: | 错误处理 | 中 |
| AAWEBootChecker | shouldCheckTargetPath: | 启动检测 | 中 |

---

## 下一步

1. 用Frida脚本确认根因
2. 编写dylib实现上述hook
3. 注入测试
4. 根据日志调整策略
