// hook_cache_classes.js
// Hook 所有可能的缓存类，强制走网络
console.log('[*] 缓存破坏器启动...');

// 1. Hook NSURLCache - 标准 HTTP 缓存
console.log('[1] Hook NSURLCache');
if (ObjC.classes.NSURLCache) {
    var cache = ObjC.classes.NSURLCache;

    Interceptor.attach(cache['- cachedResponseForRequest:'].implementation, {
        onEnter: function(args) {
            try {
                var req = new ObjC.Object(args[2]);
                var url = req.URL().absoluteString().toString();
                if (url.indexOf('profile') >= 0 || url.indexOf('user') >= 0) {
                    console.log('[NSURLCache] 拦截缓存请求: ' + url);
                    this.shouldBlock = true;
                }
            } catch(e) {}
        },
        onLeave: function(ret) {
            if (this.shouldBlock) {
                ret.replace(ptr(0));  // 返回 nil，强制走网络
                console.log('[NSURLCache] 已阻止缓存返回');
            }
        }
    });
}

// 2. 查找所有包含 Cache 的类
console.log('[2] 枚举所有 Cache 类');
var cacheClasses = [];
Object.keys(ObjC.classes).forEach(function(name) {
    if (name.indexOf('Cache') >= 0 || name.indexOf('cache') >= 0) {
        cacheClasses.push(name);
    }
});

console.log('[*] 找到 ' + cacheClasses.length + ' 个缓存相关类:');
cacheClasses.forEach(function(name) {
    console.log('  - ' + name);
});

// 3. Hook 可疑的缓存类
var targetCacheClasses = [
    'TTKProfileCache',
    'AWEUserCache',
    'TTNetworkCache',
    'TTKUserCache',
    'AWEProfileCache'
];

targetCacheClasses.forEach(function(className) {
    if (ObjC.classes[className]) {
        console.log('[3] Hook ' + className);
        var cls = ObjC.classes[className];

        // Hook 所有方法
        cls.$ownMethods.forEach(function(method) {
            try {
                Interceptor.attach(cls[method].implementation, {
                    onEnter: function(args) {
                        console.log('[' + className + '] 调用: ' + method);

                        // 如果是返回缓存对象的方法，记录下来
                        if (method.indexOf('cached') >= 0 ||
                            method.indexOf('get') >= 0 ||
                            method.indexOf('fetch') >= 0) {
                            this.isCacheGetter = true;
                        }
                    },
                    onLeave: function(ret) {
                        if (this.isCacheGetter && ret && !ret.isNull()) {
                            console.log('[' + className + '] 返回缓存对象');
                            ret.replace(ptr(0));  // 清除缓存，强制重新请求
                        }
                    }
                });
            } catch(e) {}
        });
    }
});

// 4. Hook 单例模式的 sharedInstance/sharedCache
console.log('[4] Hook 单例缓存');
cacheClasses.forEach(function(className) {
    var cls = ObjC.classes[className];
    if (!cls) return;

    var singletonMethods = [
        '+ sharedInstance',
        '+ sharedCache',
        '+ shared',
        '+ defaultCache'
    ];

    singletonMethods.forEach(function(method) {
        if (cls[method]) {
            try {
                Interceptor.attach(cls[method].implementation, {
                    onEnter: function(args) {
                        console.log('[Singleton] ' + className + ' ' + method);
                    },
                    onLeave: function(ret) {
                        // 可以返回 nil 完全禁用缓存
                        // ret.replace(ptr(0));
                    }
                });
            } catch(e) {}
        }
    });
});

// 5. Hook NSUserDefaults 的 profile 相关 key
console.log('[5] Hook NSUserDefaults profile keys');
var defaults = ObjC.classes.NSUserDefaults;
Interceptor.attach(defaults['- objectForKey:'].implementation, {
    onEnter: function(args) {
        var key = new ObjC.Object(args[2]).toString();
        var profileKeys = ['profile', 'user', 'self', 'current', 'me'];

        for (var i = 0; i < profileKeys.length; i++) {
            if (key.toLowerCase().indexOf(profileKeys[i]) >= 0) {
                console.log('[NSUserDefaults] 拦截 key: ' + key);
                this.shouldBlock = true;
                break;
            }
        }
    },
    onLeave: function(ret) {
        if (this.shouldBlock && ret && !ret.isNull()) {
            console.log('[NSUserDefaults] 清除缓存返回值');
            ret.replace(ptr(0));  // 返回 nil
        }
    }
});

console.log('\n[*] 缓存破坏器就绪');
console.log('[*] 现在操作 App，所有缓存将被清除，强制走网络');
console.log('[*] 请进入个人主页...');
