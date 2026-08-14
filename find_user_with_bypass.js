// ========== 反检测部分 ==========
console.log('[*] 加载反检测...');

var ptrace = Module.findExportByName(null, 'ptrace');
if (ptrace) {
    Interceptor.replace(ptrace, new NativeCallback(function() { return 0; }, 'int', ['int', 'int', 'pointer', 'int']));
}

var sysctl = Module.findExportByName(null, 'sysctl');
if (sysctl) {
    Interceptor.attach(sysctl, {
        onLeave: function(retval) {
            try {
                var mib = this.context.r0 || this.context.x0;
                if (mib) {
                    var name = ptr(mib).readPointer();
                    if (name.readU32() === 1 && name.add(4).readU32() === 14) {
                        var info = ptr(mib).add(8).readPointer();
                        if (info) {
                            var flags = info.add(32);
                            flags.writeU32(flags.readU32() & ~0x800);
                        }
                    }
                }
            } catch(e) {}
        }
    });
}

var strstr = Module.findExportByName(null, 'strstr');
if (strstr) {
    Interceptor.attach(strstr, {
        onEnter: function(args) {
            try {
                this.needle = Memory.readUtf8String(args[1]);
            } catch(e) {}
        },
        onLeave: function(retval) {
            if (this.needle && (this.needle.indexOf('frida') >= 0 || this.needle.indexOf('gum') >= 0)) {
                retval.replace(ptr(0));
            }
        }
    });
}

console.log('[+] 反检测加载完成\n');

// ========== 枚举 User 类 ==========
console.log('[*] 等待3秒后开始枚举...\n');

setTimeout(function() {
    console.log('[*] 开始枚举 User 相关类...\n');

    var userClasses = [];
    var profileClasses = [];

    for (var className in ObjC.classes) {
        var lower = className.toLowerCase();
        if (lower.indexOf('user') >= 0 && lower.indexOf('default') < 0 && lower.indexOf('nsuserdefaults') < 0) {
            userClasses.push(className);
        }
        if (lower.indexOf('profile') >= 0) {
            profileClasses.push(className);
        }
    }

    console.log('========== User 类 (' + userClasses.length + ' 个) ==========');
    userClasses.slice(0, 80).forEach(function(name) {
        console.log('  ' + name);
    });

    console.log('\n========== Profile 类 (' + profileClasses.length + ' 个) ==========');
    profileClasses.slice(0, 80).forEach(function(name) {
        console.log('  ' + name);
    });

    console.log('\n[*] 枚举完成！请查看上面的类名，找到可能的用户数据类');

}, 3000);
