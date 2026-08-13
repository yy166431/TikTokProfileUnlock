// TikTok无网络连接诊断脚本
// 运行: frida -U -f com.zhiliaoapp.musically -l frida_diagnose.js --no-pause

console.log("\n[*] ====== TikTok网络诊断启动 ======\n");

// 1. Hook BDTuringSparkManager - 风控验证
if (ObjC.classes.BDTuringSparkManager) {
    console.log("[+] 找到 BDTuringSparkManager");

    var BDTuring = ObjC.classes.BDTuringSparkManager;

    // verifyWithCompletion:
    var verifyMethod = BDTuring["- verifyWithCompletion:"];
    if (verifyMethod) {
        Interceptor.attach(verifyMethod.implementation, {
            onEnter: function(args) {
                console.log("\n[BDTuring] verifyWithCompletion 被调用");
                this.completion = new ObjC.Block(args[2]);
            },
            onLeave: function(retval) {
                console.log("[BDTuring] verifyWithCompletion 返回");
            }
        });
    }

    // loadSettings:completion:
    var loadMethod = BDTuring["- loadSettings:completion:"];
    if (loadMethod) {
        Interceptor.attach(loadMethod.implementation, {
            onEnter: function(args) {
                console.log("[BDTuring] loadSettings 被调用");
            }
        });
    }
} else {
    console.log("[-] 未找到 BDTuringSparkManager");
}

// 2. Hook NetworkReachabilityManager - 网络检测
if (ObjC.classes.NetworkReachabilityManager) {
    console.log("[+] 找到 NetworkReachabilityManager");

    var NetworkMgr = ObjC.classes.NetworkReachabilityManager;

    var isReachable = NetworkMgr["- isReachable"];
    if (isReachable) {
        Interceptor.attach(isReachable.implementation, {
            onLeave: function(retval) {
                var result = retval ? "YES" : "NO";
                console.log("[Network] isReachable = " + result);
            }
        });
    }

    var status = NetworkMgr["- currentReachabilityStatus"];
    if (status) {
        Interceptor.attach(status.implementation, {
            onLeave: function(retval) {
                var statusMap = {0: "不可达", 1: "蜂窝", 2: "WiFi"};
                console.log("[Network] currentReachabilityStatus = " + (statusMap[retval.toInt32()] || retval));
            }
        });
    }
} else {
    console.log("[-] 未找到 NetworkReachabilityManager");
}

// 3. Hook TTHttpTask - HTTP请求
if (ObjC.classes.TTHttpTask) {
    console.log("[+] 找到 TTHttpTask");

    var TTHttp = ObjC.classes.TTHttpTask;

    var resume = TTHttp["- resume"];
    if (resume) {
        Interceptor.attach(resume.implementation, {
            onEnter: function(args) {
                var self = new ObjC.Object(args[0]);
                try {
                    var request = self.$ivars['_request'];
                    if (request) {
                        var url = request.URL();
                        if (url) {
                            console.log("\n[HTTP] 发起请求: " + url.toString());

                            var headers = request.allHTTPHeaderFields();
                            if (headers) {
                                var headerDict = new ObjC.Object(headers);
                                console.log("[HTTP] X-Gorgon: " + (headerDict.objectForKey_("X-Gorgon") || "(无)"));
                                console.log("[HTTP] X-Khronos: " + (headerDict.objectForKey_("X-Khronos") || "(无)"));
                                console.log("[HTTP] X-Argus: " + (headerDict.objectForKey_("X-Argus") || "(无)"));
                                console.log("[HTTP] device_id: " + (headerDict.objectForKey_("device_id") || "(无)"));
                            }
                        }
                    }
                } catch(e) {
                    console.log("[HTTP] 读取请求信息失败: " + e);
                }
            }
        });
    }

    // didCompleteWithError:
    var complete = TTHttp["- didCompleteWithError:"];
    if (complete) {
        Interceptor.attach(complete.implementation, {
            onEnter: function(args) {
                var error = new ObjC.Object(args[2]);
                if (error && !error.isNull()) {
                    console.log("\n[HTTP] 请求失败!");
                    console.log("[HTTP] Error Code: " + error.code());
                    console.log("[HTTP] Error Domain: " + error.domain());
                    console.log("[HTTP] Error Description: " + error.localizedDescription());
                } else {
                    console.log("[HTTP] 请求成功");
                }
            }
        });
    }
} else {
    console.log("[-] 未找到 TTHttpTask");
}

// 4. Hook TTNetworkManager - 错误处理
if (ObjC.classes.TTNetworkManager) {
    console.log("[+] 找到 TTNetworkManager");

    var TTNet = ObjC.classes.TTNetworkManager;

    var handleError = TTNet["- handleNetworkError:"];
    if (handleError) {
        Interceptor.attach(handleError.implementation, {
            onEnter: function(args) {
                var error = new ObjC.Object(args[2]);
                if (error && !error.isNull()) {
                    console.log("\n[NetworkMgr] 处理网络错误:");
                    console.log("[NetworkMgr] Code: " + error.code());
                    console.log("[NetworkMgr] Domain: " + error.domain());
                    console.log("[NetworkMgr] Description: " + error.localizedDescription());

                    var userInfo = error.userInfo();
                    if (userInfo) {
                        console.log("[NetworkMgr] UserInfo: " + userInfo.toString());
                    }
                }
            }
        });
    }
} else {
    console.log("[-] 未找到 TTNetworkManager");
}

// 5. Hook NSUserDefaults - device_id读取
if (ObjC.classes.NSUserDefaults) {
    console.log("[+] Hook NSUserDefaults");

    var defaults = ObjC.classes.NSUserDefaults;

    var objectForKey = defaults["- objectForKey:"];
    Interceptor.attach(objectForKey.implementation, {
        onEnter: function(args) {
            var key = new ObjC.Object(args[2]);
            var keyStr = key.toString();
            if (keyStr.indexOf("DeviceID") !== -1 || keyStr === "kDeviceIDStorageKey") {
                this.isDeviceID = true;
                this.key = keyStr;
            }
        },
        onLeave: function(retval) {
            if (this.isDeviceID) {
                var value = new ObjC.Object(retval);
                console.log("\n[DeviceID] 读取Key: " + this.key);
                console.log("[DeviceID] 返回值: " + (value.isNull() ? "(null)" : value.toString()));
            }
        }
    });
}

// 6. Hook NSURLSession dataTaskWithRequest - 最底层网络
if (ObjC.classes.NSURLSession) {
    console.log("[+] Hook NSURLSession");

    var session = ObjC.classes.NSURLSession;

    var dataTask = session["- dataTaskWithRequest:completionHandler:"];
    if (dataTask) {
        Interceptor.attach(dataTask.implementation, {
            onEnter: function(args) {
                var request = new ObjC.Object(args[2]);
                var url = request.URL();
                if (url && url.toString().indexOf("tiktok") !== -1) {
                    console.log("\n[NSURLSession] 创建任务: " + url.toString());
                }
            }
        });
    }
}

// 7. 监控关键字符串（可能的错误提示）
Interceptor.attach(ObjC.classes.NSString["- isEqualToString:"].implementation, {
    onEnter: function(args) {
        var self = new ObjC.Object(args[0]);
        var other = new ObjC.Object(args[2]);
        var selfStr = self.toString();
        var otherStr = other.toString();

        if (selfStr.indexOf("网络") !== -1 || selfStr.indexOf("network") !== -1 ||
            otherStr.indexOf("网络") !== -1 || otherStr.indexOf("network") !== -1) {
            console.log("\n[字符串比较] '" + selfStr + "' == '" + otherStr + "'");
        }
    }
});

console.log("\n[*] ====== Hook安装完成，开始监控 ======\n");
