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
