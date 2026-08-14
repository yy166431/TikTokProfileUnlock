// Anti-anti-debug for TikTok
console.log('[*] Bypassing anti-debug checks...');

if (ObjC.available) {
    // 1. Hook sysctl to hide debugger
    var sysctl = Module.findExportByName(null, 'sysctl');
    if (sysctl) {
        Interceptor.attach(sysctl, {
            onEnter: function(args) {
                this.name = args[0];
            },
            onLeave: function(retval) {
                // Check if querying P_TRACED flag
                if (this.name) {
                    var name = this.name.readPointer();
                    if (name.readU32() === 1 && name.add(4).readU32() === 14) {
                        // CTL_KERN, KERN_PROC - hide P_TRACED
                        var info = this.name.add(8).readPointer();
                        if (info) {
                            var flags = info.add(32);
                            flags.writeU32(flags.readU32() & ~0x800);
                        }
                    }
                }
            }
        });
        console.log('[+] Hooked sysctl');
    }

    // 2. Hook ptrace
    var ptrace = Module.findExportByName(null, 'ptrace');
    if (ptrace) {
        Interceptor.replace(ptrace, new NativeCallback(function() {
            return 0;
        }, 'int', ['int', 'int', 'pointer', 'int']));
        console.log('[+] Hooked ptrace');
    }

    // 3. Hook getppid
    var getppid = Module.findExportByName(null, 'getppid');
    if (getppid) {
        Interceptor.replace(getppid, new NativeCallback(function() {
            return 1; // Return init as parent
        }, 'int', []));
        console.log('[+] Hooked getppid');
    }
}

console.log('[*] Anti-debug bypass complete. Loading main script...\n');
// enum_all_objects.js
// 暴力枚举所有运行时对象，找 profile 数据
console.log('[*] 开始枚举所有运行时对象...');

var found = 0;
ObjC.choose(ObjC.classes.NSObject, {
    onMatch: function(obj) {
        try {
            var className = obj.$className;

            // 只看可能的用户数据类
            if (className.indexOf('User') < 0 &&
                className.indexOf('Profile') < 0 &&
                className.indexOf('TTK') !== 0 &&
                className.indexOf('AWE') !== 0) {
                return;
            }

            // 尝试调用 description
            var desc = '';
            try {
                desc = obj.description().toString();
            } catch(e) {
                desc = obj.toString();
            }

            // 检查特征
            if (desc.indexOf('sec_uid') >= 0 ||
                desc.indexOf('follower') >= 0 ||
                desc.indexOf('unique_id') >= 0) {

                found++;
                console.log('\n[' + found + '] 类: ' + className);
                console.log('地址: ' + obj.handle);
                console.log('内容:\n' + desc.substring(0, 800));
                console.log('---');

                send({
                    type: 'profile_object',
                    className: className,
                    address: obj.handle.toString(),
                    content: desc
                });
            }
        } catch(e) {}
    },
    onComplete: function() {
        console.log('\n[*] 扫描完成，找到 ' + found + ' 个疑似对象');
    }
});
