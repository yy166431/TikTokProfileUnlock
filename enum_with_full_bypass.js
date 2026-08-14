// 完整反检测 + 内存对象枚举
console.log('[*] 加载完整反检测...');

// ============ 第一步：反检测 ============
if (ObjC.available) {
    // 1. Hook frida 字符串检测
    var strcmp = Module.findExportByName(null, 'strcmp');
    if (strcmp) {
        Interceptor.attach(strcmp, {
            onEnter: function(args) {
                var str1 = args[0].readCString();
                var str2 = args[1].readCString();
                if ((str1 && str1.toLowerCase().indexOf('frida') >= 0) ||
                    (str2 && str2.toLowerCase().indexOf('frida') >= 0)) {
                    args[0] = ptr(0);
                    args[1] = ptr(1);
                }
            }
        });
    }

    // 2. Hook dlopen/dlsym 防检测 frida-agent
    var dlopen = Module.findExportByName(null, 'dlopen');
    if (dlopen) {
        Interceptor.attach(dlopen, {
            onEnter: function(args) {
                var path = args[0].readCString();
                if (path && path.indexOf('frida') >= 0) {
                    args[0] = Memory.allocUtf8String('/dev/null');
                }
            }
        });
    }

    // 3. Hook sysctl 隐藏调试器
    var sysctl = Module.findExportByName(null, 'sysctl');
    if (sysctl) {
        Interceptor.attach(sysctl, {
            onLeave: function(retval) {
                // 清除 P_TRACED 标志
                var info = this.context.x1;
                if (info) {
                    try {
                        var flags = ptr(info).add(32);
                        flags.writeU32(flags.readU32() & ~0x800);
                    } catch(e) {}
                }
            }
        });
    }

    // 4. Hook ptrace
    var ptrace = Module.findExportByName(null, 'ptrace');
    if (ptrace) {
        Interceptor.replace(ptrace, new NativeCallback(function() {
            return 0;
        }, 'int', ['int', 'int', 'pointer', 'int']));
    }

    console.log('[+] 反检测已加载');
}

// ============ 第二步：延迟5秒，等待 TikTok 初始化 ============
console.log('[*] 等待5秒后开始枚举...');
setTimeout(function() {
    console.log('[*] 开始枚举内存对象...\n');

    var found = 0;
    ObjC.choose(ObjC.classes.NSObject, {
        onMatch: function(obj) {
            try {
                var className = obj.$className;

                // 先过滤明显无关的类
                if (className.indexOf('User') < 0 &&
                    className.indexOf('Profile') < 0 &&
                    className.indexOf('Account') < 0 &&
                    className.indexOf('TTK') !== 0 &&
                    className.indexOf('AWE') !== 0) {
                    return;
                }

                // 尝试转字符串
                var desc = '';
                try {
                    desc = obj.description().toString();
                } catch(e) {
                    try {
                        desc = obj.toString();
                    } catch(e2) {
                        return;
                    }
                }

                // 检查是否包含用户数据特征
                var hasData = (desc.indexOf('sec_uid') >= 0 ||
                               desc.indexOf('follower') >= 0 ||
                               desc.indexOf('unique_id') >= 0 ||
                               desc.indexOf('aweme_count') >= 0);

                if (hasData) {
                    found++;
                    console.log('\n========== [' + found + '] ==========');
                    console.log('类名: ' + className);
                    console.log('地址: ' + obj.handle);
                    console.log('内容预览:\n' + desc.substring(0, 1000));
                    console.log('================================\n');

                    send({
                        type: 'profile_found',
                        className: className,
                        address: obj.handle.toString(),
                        preview: desc.substring(0, 2000)
                    });
                }
            } catch(e) {}
        },
        onComplete: function() {
            console.log('\n[✓] 扫描完成！共找到 ' + found + ' 个用户数据对象');
            if (found === 0) {
                console.log('[!] 没找到用户数据。请确保：');
                console.log('    1. TikTok 已登录');
                console.log('    2. 进入了个人主页（点右下角"我"）');
                console.log('    3. 等待页面加载完成');
            }
        }
    });
}, 5000);
