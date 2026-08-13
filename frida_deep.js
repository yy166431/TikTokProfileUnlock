console.log("[*] ====== TikTok深度网络诊断 ======\n");

// Hook 底层C函数 - socket创建
var socketAddr = Module.findExportByName(null, "socket");
if (socketAddr) {
    Interceptor.attach(socketAddr, {
        onEnter: function(args) {
            console.log("[socket] 创建socket: domain=" + args[0] + ", type=" + args[1] + ", protocol=" + args[2]);
        },
        onLeave: function(retval) {
            console.log("[socket] 返回fd=" + retval);
        }
    });
    console.log("[+] Hook socket 成功");
} else {
    console.log("[-] 未找到 socket 函数");
}

// Hook connect - 检测是否有连接尝试
var connectAddr = Module.findExportByName(null, "connect");
if (connectAddr) {
    Interceptor.attach(connectAddr, {
        onEnter: function(args) {
            var sockfd = args[0];
            console.log("[connect] fd=" + sockfd + ", 尝试连接...");
        },
        onLeave: function(retval) {
            console.log("[connect] 返回: " + retval + " (0=成功, -1=失败)");
        }
    });
    console.log("[+] Hook connect 成功");
} else {
    console.log("[-] 未找到 connect 函数");
}

// Hook getaddrinfo - DNS解析
var getaddrinfoAddr = Module.findExportByName(null, "getaddrinfo");
if (getaddrinfoAddr) {
    Interceptor.attach(getaddrinfoAddr, {
        onEnter: function(args) {
            var hostname = args[0];
            if (hostname && !hostname.isNull()) {
                console.log("[getaddrinfo] DNS解析: " + Memory.readUtf8String(hostname));
            }
        },
        onLeave: function(retval) {
            console.log("[getaddrinfo] 返回: " + retval + " (0=成功)");
        }
    });
    console.log("[+] Hook getaddrinfo 成功");
} else {
    console.log("[-] 未找到 getaddrinfo 函数");
}

// Hook CFNetwork的核心函数
try {
    var CFNetworkModule = Process.findModuleByName("CFNetwork");
    if (CFNetworkModule) {
        console.log("[+] 找到 CFNetwork 模块: " + CFNetworkModule.base);
    }
} catch(e) {
    console.log("[-] CFNetwork 模块查找失败");
}

// Hook NSURLSession的所有初始化
if (ObjC.available) {
    var NSURLSession = ObjC.classes.NSURLSession;
    if (NSURLSession) {
        console.log("[+] Hook NSURLSession 所有方法");

        // dataTaskWithRequest
        Interceptor.attach(NSURLSession['- dataTaskWithRequest:'].implementation, {
            onEnter: function(args) {
                var request = new ObjC.Object(args[2]);
                console.log("\n[NSURLSession dataTaskWithRequest]");
                console.log("  URL: " + request.URL().absoluteString());
            }
        });

        // dataTaskWithURL
        Interceptor.attach(NSURLSession['- dataTaskWithURL:'].implementation, {
            onEnter: function(args) {
                var url = new ObjC.Object(args[2]);
                console.log("\n[NSURLSession dataTaskWithURL]");
                console.log("  URL: " + url.absoluteString());
            }
        });
    }
}

// Hook exit/abort - 检测是否自杀
var exitAddr = Module.findExportByName(null, "exit");
if (exitAddr) {
    Interceptor.attach(exitAddr, {
        onEnter: function(args) {
            console.log("\n⚠️⚠️⚠️ [exit] 进程即将退出! 退出码=" + args[0]);
        }
    });
    console.log("[+] Hook exit 成功");
} else {
    console.log("[-] 未找到 exit 函数");
}

var abortAddr = Module.findExportByName(null, "abort");
if (abortAddr) {
    Interceptor.attach(abortAddr, {
        onEnter: function(args) {
            console.log("\n⚠️⚠️⚠️ [abort] 进程即将abort!");
        }
    });
    console.log("[+] Hook abort 成功");
} else {
    console.log("[-] 未找到 abort 函数");
}

console.log("\n[*] ====== 深度Hook安装完成，开始监控 ======\n");
