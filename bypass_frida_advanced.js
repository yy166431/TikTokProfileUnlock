// 增强版 Frida 反检测 for TikTok
console.log('[*] 加载增强反检测模块...\n');

// ========== 1. 隐藏 frida-server 进程 ==========
var fopen = Module.findExportByName(null, 'fopen');
if (fopen) {
    Interceptor.attach(fopen, {
        onEnter: function(args) {
            var path = Memory.readUtf8String(args[0]);
            if (path && (path.indexOf('/proc') === 0 || path.indexOf('/sys') === 0)) {
                this.is_proc = true;
                this.path = path;
            }
        },
        onLeave: function(retval) {
            if (this.is_proc && !retval.isNull()) {
                // 记录文件句柄，用于后续过滤
                this.fileHandle = retval;
            }
        }
    });
}

// ========== 2. 过滤 /proc/self/maps 中的 frida 字符串 ==========
var fgets = Module.findExportByName(null, 'fgets');
if (fgets) {
    Interceptor.attach(fgets, {
        onLeave: function(retval) {
            if (retval.isNull()) return;
            var line = Memory.readUtf8String(retval);
            if (line && (line.indexOf('frida') >= 0 || line.indexOf('gum-js-loop') >= 0 || line.indexOf('gmain') >= 0)) {
                // 替换为空行
                Memory.writeUtf8String(retval, '');
            }
        }
    });
}

// ========== 3. Hook strstr/strcmp 防止字符串检测 ==========
var strstr = Module.findExportByName(null, 'strstr');
if (strstr) {
    Interceptor.attach(strstr, {
        onEnter: function(args) {
            this.haystack = Memory.readUtf8String(args[0]);
            this.needle = Memory.readUtf8String(args[1]);
        },
        onLeave: function(retval) {
            if (this.needle && (this.needle.indexOf('frida') >= 0 ||
                this.needle.indexOf('gum') >= 0 ||
                this.needle.indexOf('27042') >= 0)) {
                retval.replace(ptr(0)); // 返回 NULL
            }
        }
    });
}

// ========== 4. Hook ptrace ==========
var ptrace = Module.findExportByName(null, 'ptrace');
if (ptrace) {
    Interceptor.replace(ptrace, new NativeCallback(function(request) {
        if (request === 31) { // PT_DENY_ATTACH
            return 0;
        }
        return 0;
    }, 'int', ['int', 'int', 'pointer', 'int']));
    console.log('[+] Hooked ptrace');
}

// ========== 5. Hook sysctl 隐藏调试器 ==========
var sysctl = Module.findExportByName(null, 'sysctl');
if (sysctl) {
    Interceptor.attach(sysctl, {
        onEnter: function(args) {
            this.name = args[0];
        },
        onLeave: function(retval) {
            if (this.name) {
                var name = this.name.readPointer();
                if (name.readU32() === 1 && name.add(4).readU32() === 14) {
                    var info = this.name.add(8).readPointer();
                    if (info) {
                        var flags = info.add(32);
                        flags.writeU32(flags.readU32() & ~0x800); // 清除 P_TRACED
                    }
                }
            }
        }
    });
    console.log('[+] Hooked sysctl');
}

// ========== 6. Hook stat/access 隐藏 frida-server ==========
var access = Module.findExportByName(null, 'access');
if (access) {
    Interceptor.attach(access, {
        onEnter: function(args) {
            var path = Memory.readUtf8String(args[0]);
            if (path && path.indexOf('frida') >= 0) {
                this.block = true;
            }
        },
        onLeave: function(retval) {
            if (this.block) {
                retval.replace(-1); // 返回文件不存在
            }
        }
    });
}

// ========== 7. Hook dlsym 防止函数检测 ==========
var dlsym = Module.findExportByName(null, 'dlsym');
if (dlsym) {
    Interceptor.attach(dlsym, {
        onEnter: function(args) {
            this.symbol = Memory.readUtf8String(args[1]);
        },
        onLeave: function(retval) {
            if (this.symbol && (this.symbol.indexOf('frida') >= 0 || this.symbol.indexOf('gum') >= 0)) {
                retval.replace(ptr(0)); // 返回 NULL
            }
        }
    });
}

console.log('[+] 反检测模块加载完成！');
console.log('[*] TikTok 应该检测不到 Frida 了\n');
