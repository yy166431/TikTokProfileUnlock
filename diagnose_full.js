// diagnose_full.js
// TikTok Profile 全面诊断工具
console.log('[*] TikTok Profile 诊断工具启动');

// 1. 枚举所有 User/Profile 相关类
console.log('\n=== 第1步: 查找相关类 ===');
var relevantClasses = [];
Object.keys(ObjC.classes).forEach(function(name) {
    if (name.indexOf('User') >= 0 ||
        name.indexOf('Profile') >= 0 ||
        name.indexOf('TTK') === 0) {
        console.log('[类] ' + name);
        relevantClasses.push(name);
    }
});

// 2. 监控对象分配
console.log('\n=== 第2步: 监控对象创建 ===');
Interceptor.attach(ObjC.classes.NSObject['+ alloc'].implementation, {
    onLeave: function(ret) {
        try {
            var obj = new ObjC.Object(ret);
            var name = obj.$className;
            if (name.indexOf('User') >= 0 || name.indexOf('Profile') >= 0) {
                console.log('[alloc] ' + name);
                // 记录调用栈
                console.log(Thread.backtrace(this.context, Backtracer.ACCURATE)
                    .map(DebugSymbol.fromAddress).join('\n'));
            }
        } catch(e) {}
    }
});

// 3. Hook NSUserDefaults（可能缓存在这里）
console.log('\n=== 第3步: Hook NSUserDefaults ===');
var defaults = ObjC.classes.NSUserDefaults;
Interceptor.attach(defaults['- objectForKey:'].implementation, {
    onEnter: function(args) {
        var key = new ObjC.Object(args[2]).toString();
        if (key.indexOf('user') >= 0 || key.indexOf('profile') >= 0) {
            console.log('[NSUserDefaults] 读取: ' + key);
            this.key = key;
        }
    },
    onLeave: function(ret) {
        if (this.key && ret && !ret.isNull()) {
            try {
                var obj = new ObjC.Object(ret);
                var str = obj.toString();
                if (str.indexOf('sec_uid') >= 0) {
                    console.log('[!!!] 发现 profile 数据:');
                    console.log(str.substring(0, 500));
                    send({type: 'profile_userdefaults', key: this.key, data: str});
                }
            } catch(e) {}
        }
    }
});

// 4. Hook Keychain（可能存在设备指纹）
console.log('\n=== 第4步: Hook Keychain ===');
var keychainClass = ObjC.classes.NSObject;
try {
    Interceptor.attach(Module.findExportByName('Security', 'SecItemCopyMatching'), {
        onEnter: function(args) {
            var query = new ObjC.Object(args[0]);
            console.log('[Keychain] 查询: ' + query.toString());
        },
        onLeave: function(ret) {
            if (ret.toInt32() === 0 && this.result) {
                console.log('[Keychain] 找到数据');
            }
        }
    });
} catch(e) {
    console.log('[!] Keychain hook 失败: ' + e);
}

// 5. Hook JSON 解析（可能数据是 JSON 格式）
console.log('\n=== 第5步: Hook JSON 解析 ===');
if (ObjC.classes.NSJSONSerialization) {
    var jsonClass = ObjC.classes.NSJSONSerialization;
    Interceptor.attach(jsonClass['+ JSONObjectWithData:options:error:'].implementation, {
        onEnter: function(args) {
            this.data = new ObjC.Object(args[2]);
        },
        onLeave: function(ret) {
            try {
                if (ret && !ret.isNull()) {
                    var obj = new ObjC.Object(ret);
                    var str = obj.toString();
                    if (str.indexOf('sec_uid') >= 0 || str.indexOf('follower') >= 0) {
                        console.log('[!!!] JSON 解析出 profile:');
                        console.log(str.substring(0, 800));
                        send({type: 'profile_json', data: str});
                    }
                }
            } catch(e) {}
        }
    });
}

console.log('\n[*] 诊断工具就绪，请操作 App（进入个人主页）...');
console.log('[*] 找到的相关类数量: ' + relevantClasses.length);
