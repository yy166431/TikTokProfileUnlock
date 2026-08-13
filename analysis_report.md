# TikTok "无网络连接" 技术分析报告

## 执行概要

iPhone12 Taurine越狱环境TikTok显示"无网络连接"，iPhone17正常。根据对TikTok_Decrypted.ipa的逆向分析，这是**字节跳动风控系统拦截**，不是简单的越狱检测。

---

## 核心发现

### 1. 字节跳动加密请求头（风控核心）
TikTok所有网络请求必须携带以下加密签名头：
- **X-Gorgon**: 参数签名（最关键）
- **X-Khronos**: 时间戳签名
- **X-Argus**: 设备指纹签名
- **X-Ladon**: 反作弊签名
- **X-SS-STUB**: 安全令牌

这些请求头由**BDTuring风控SDK**实时生成，缺少或签名错误=服务器返回"无网络连接"。

### 2. BDTuring风控SDK（核心模块）
位置：`MusicallyCore.framework`
关键类：
```
BDTuringSparkManager           // 风控总调度
BDTuringViewController          // 验证界面
BDTuringSettings               // 风控配置
BDTuringVerifyResult           // 验证结果
BDTuringTwiceVerifyResponse    // 二次验证响应
```

### 3. 设备指纹系统
关键标识符：
- `device_id` - 设备唯一ID（服务器风控核心）
- `install_id` - 安装ID
- `openudid` - 开源设备ID
- `idfa/idfv` - 广告标识符

存储位置：
- Keychain: `AWEClientDeviceIDKeychainKey`
- 文件: `ttinstall_ids.plist`
- UserDefaults: `kDeviceIDStorageKey`

### 4. 网络层架构
核心类：
- `TTNetworkManager` - 网络管理器
- `TTHttpTask` - 网络任务
- `NetworkReachabilityManager` - 网络可达性检测
- `BTDNetworkReachabilityStatus` - 字节跳动网络状态

### 5. 安全框架
发现的安全模块：
- **AAWEBootChecker.framework** - 启动检测（检测hook/注入）
- **AAAASingularity.framework** - Swift运行时保护
- **TikTokSecurity.bundle** - 安全资源包
- **PIPONetworkSecurityImpl.bundle** - 网络安全实现

---

## 根因分析

### iPhone12被拦截的3个可能原因：

#### 原因1：设备指纹风控（最可能）
- iPhone12的`device_id`可能已被字节跳动风控系统标记
- 越狱环境特征（Substrate/fishhook残留）被BDTuring检测
- 历史违规行为（多次触发风控）导致device_id拉黑

#### 原因2：X-Gorgon签名失败
- 越狱环境修改了系统时间/时区导致X-Khronos时间戳错误
- Taurine越狱修改的系统库影响加密算法
- BDTuring无法正确生成签名=服务器拒绝请求

#### 原因3：网络环境检测
- iPhone12使用的DNS/代理被TikTok识别为异常
- TTNetworkManager的`NetworkReachabilityManager`检测到可疑网络配置
- SCNetworkReachability标记iPhone12网络为不可信

---

## Hook方案（绕过风控）

### 方案A：绕过BDTuring验证（推荐）
Hook点：
```objc
// 1. 强制BDTuring验证成功
@interface BDTuringSparkManager : NSObject
- (void)verifyWithCompletion:(void (^)(BDTuringVerifyResult *))completion;
@end

// Hook实现
%hook BDTuringSparkManager
- (void)verifyWithCompletion:(void (^)(id))completion {
    // 伪造成功结果
    id fakeResult = [[objc_getClass("BDTuringVerifyResult") alloc] init];
    [fakeResult setValue:@YES forKey:@"success"];
    [fakeResult setValue:@"bypass" forKey:@"verifyId"];
    completion(fakeResult);
}
%end
```

### 方案B：替换设备指纹
Hook点：
```objc
// Keychain设备ID
%hook AWEClientDeviceIDKeychainWrapper
- (NSString *)deviceID {
    return @"新的干净device_id"; // 从iPhone17复制
}
%end

// 存储的设备ID
%hook NSUserDefaults
- (id)objectForKey:(NSString *)key {
    if ([key isEqualToString:@"kDeviceIDStorageKey"]) {
        return @"新的device_id";
    }
    return %orig;
}
%end
```

### 方案C：放行所有网络请求
Hook点：
```objc
// NetworkReachabilityManager
%hook NetworkReachabilityManager
- (BTDNetworkReachabilityStatus)currentReachabilityStatus {
    return 2; // ReachableViaWiFi
}
- (BOOL)isReachable {
    return YES;
}
%end

// TTNetworkManager错误处理
%hook TTNetworkManager
- (void)handleNetworkError:(NSError *)error {
    // 吞掉所有网络错误
}
%end
```

### 方案D：绕过请求头验证
Hook点：
```objc
// TTHttpTask请求拦截
%hook TTHttpTask
- (void)resume {
    NSMutableURLRequest *request = [self valueForKey:@"_request"];
    
    // 确保关键请求头存在（从正常设备抓包获取）
    if (![request valueForHTTPHeaderField:@"X-Gorgon"]) {
        [request setValue:@"伪造的Gorgon签名" forHTTPHeaderField:@"X-Gorgon"];
    }
    if (![request valueForHTTPHeaderField:@"X-Khronos"]) {
        [request setValue:@([[NSDate date] timeIntervalSince1970]) forHTTPHeaderField:@"X-Khronos"];
    }
    
    %orig;
}
%end
```

---

## 实施步骤

### 第1步：确认根因
```bash
# 在iPhone12上运行Frida脚本
frida -U -f com.zhiliaoapp.musically -l diagnose.js

# diagnose.js内容：
Interceptor.attach(Module.findExportByName("MusicallyCore", "_ZN*BDTuringSparkManager*"), {
    onEnter: function(args) {
        console.log("[BDTuring] Verify called");
    },
    onLeave: function(retval) {
        console.log("[BDTuring] Result:", retval);
    }
});

Interceptor.attach(ObjC.classes.TTHttpTask["- resume"].implementation, {
    onEnter: function(args) {
        var request = ObjC.Object(args[0]).request();
        var headers = request.allHTTPHeaderFields();
        console.log("[Network] Headers:", headers);
    }
});
```

### 第2步：编写dylib
创建`TikTokBypass.dylib`（基于方案A+B+C）：
```objc
%hook BDTuringSparkManager
- (void)verifyWithCompletion:(void (^)(id))completion {
    id result = [[objc_getClass("BDTuringVerifyResult") alloc] init];
    [result setValue:@YES forKey:@"success"];
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
        return @"干净的device_id"; // 从iPhone17提取
    }
    return %orig;
}
%end

%ctor {
    NSLog(@"[TikTokBypass] Loaded");
}
```

### 第3步：注入dylib
使用insert_dylib或直接修改MachO：
```bash
# 方法1：insert_dylib（巨魔）
insert_dylib @executable_path/TikTokBypass.dylib TikTok --inplace

# 方法2：手动注入（越狱环境）
cp TikTokBypass.dylib /Library/MobileSubstrate/DynamicLibraries/
echo "com.zhiliaoapp.musically" > /Library/MobileSubstrate/DynamicLibraries/TikTokBypass.plist
killall -9 TikTok
```

### 第4步：验证
```bash
# 查看日志
idevicesyslog | grep "TikTokBypass\|BDTuring\|Network"

# 抓包验证（PC上mitmproxy）
mitmdump -p 8888 --host
# iPhone12设置代理192.168.x.x:8888
# 查看是否有api.tiktokv.com的请求通过
```

---

## 关键文件位置

```
TikTok.app/
├── TikTok                                  // 主二进制（91KB，仅壳）
├── Frameworks/
│   ├── MusicallyCore.framework/            // 核心逻辑（769MB）
│   │   └── MusicallyCore                  // 所有业务+风控代码
│   ├── AAWEBootChecker.framework/          // 启动检测
│   └── AAAASingularity.framework/          // 运行时保护
├── TikTokSecurity.bundle/                  // 安全资源
├── PIPONetworkSecurityImpl.bundle/         // 网络安全实现
└── BDTuringResource.bundle/                // 风控资源（验证码等）
```

---

## 注意事项

1. **X-Gorgon签名极难伪造**：算法在native层（C++），参数包括URL、body、device_id、时间戳，需要逆向`MusicallyCore`的加密函数
2. **device_id一旦被封很难恢复**：重装App无效，需要还原系统或修改硬件标识符
3. **BDTuring会定期更新检测逻辑**：hook方案可能随版本失效
4. **不要在hook环境登录账号**：可能导致账号被风控

---

## 下一步行动

1. **提取iPhone17的device_id**：
   - 越狱后读取`/var/mobile/Containers/Data/Application/<TikTok>/Library/Preferences/com.zhiliaoapp.musically.plist`
   - 或Keychain中的`AWEClientDeviceIDKeychainKey`

2. **抓包对比**：
   - 用Charles/mitmproxy对比iPhone12和iPhone17的HTTP请求头差异
   - 重点看X-Gorgon/X-Khronos/X-Argus的值

3. **编写诊断工具**：
   - Frida脚本实时监控BDTuring调用和返回值
   - Hook NSURLSession查看服务器返回的错误码

4. **终极方案**：
   - 完全还原iPhone12系统（DFU模式刷机）
   - 或用iPhone17的完整设备指纹（需要越狱+文件系统访问权限）

---

**结论**：这不是越狱检测，是字节跳动的设备风控系统在起作用。iPhone12的设备指纹或历史行为触发了风控规则，导致BDTuring拒绝生成有效的网络签名，服务器返回"无网络连接"的友好提示。
