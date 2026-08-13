// TikTok安全检测扫描脚本
console.log("[*] ====== TikTok安全检测扫描 ======\n");

// 监控可疑的安全检测类
var securityClasses = [
    "AAWEBootChecker",
    "AAAASingularity",
    "AWESecurityDetector",
    "TTSecurityChecker",
    "BDTuringSpark"
];

if (ObjC.available) {
    console.log("[+] ObjC运行时可用，开始扫描安全类...\n");

    for (var i = 0; i < securityClasses.length; i++) {
        var className = securityClasses[i];
        try {
            var cls = ObjC.classes[className];
            if (cls) {
                console.log("[!!!] 找到安全类: " + className);

                // 枚举所有方法
                var methods = cls.$ownMethods;
                console.log("  方法列表:");
                for (var j = 0; j < Math.min(methods.length, 20); j++) {
                    console.log("    " + methods[j]);
                }
                console.log("");
            }
        } catch(e) {
            // 类不存在
        }
    }

    // 监控NSThread创建 - 找守护线程
    console.log("[+] Hook NSThread 创建");
    Interceptor.attach(ObjC.classes.NSThread['+ detachNewThreadSelector:toTarget:withObject:'].implementation, {
        onEnter: function(args) {
            var selector = ObjC.selectorAsString(args[2]);
            var target = new ObjC.Object(args[3]);
            console.log("\n[NSThread] 创建新线程:");
            console.log("  Selector: " + selector);
            console.log("  Target: " + target.$className);
        }
    });

    // 监控dispatch_after - 延迟检测
    var dispatch_after = new NativeFunction(
        Module.findExportByName(null, "dispatch_after"),
        'void', ['pointer', 'pointer', 'pointer']
    );

    Interceptor.replace(dispatch_after, new NativeCallback(function(when, queue, block) {
        console.log("\n[dispatch_after] 延迟任务被调度");
        dispatch_after(when, queue, block);
    }, 'void', ['pointer', 'pointer', 'pointer']));

    // Hook dlopen - 检测动态库加载
    var dlopen = Module.findExportByName(null, "dlopen");
    if (dlopen) {
        Interceptor.attach(dlopen, {
            onEnter: function(args) {
                var path = Memory.readUtf8String(args[0]);
                if (path && (path.indexOf("Security") != -1 || path.indexOf("Check") != -1)) {
                    console.log("\n[dlopen] 加载安全库: " + path);
                }
            }
        });
    }

    // Hook exit - 检测是否自杀
    var exit_func = Module.findExportByName(null, "exit");
    if (exit_func) {
        Interceptor.attach(exit_func, {
            onEnter: function(args) {
                console.log("\n⚠️⚠️⚠️ [exit] 进程即将退出! 退出码=" + args[0]);
                console.log("调用栈:");
                console.log(Thread.backtrace(this.context, Backtracer.ACCURATE)
                    .map(DebugSymbol.fromAddress).join('\n'));
            }
        });
    }
}

console.log("\n[*] ====== 监控已启动，观察3-5秒后的行为 ======\n");
