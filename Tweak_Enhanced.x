// ==================== 增强版：调试和深度反射 ====================
// 在 constructor 中添加，用于验证类和方法是否存在

__attribute__((constructor))
static void debugNetworkClasses() {
    NSLog(@"[TKCapture] ==================== DEBUG MODE ====================");

    // 1. 验证 TTHttpTask 类是否存在
    Class ttHttpTaskClass = objc_getClass("TTHttpTask");
    if (ttHttpTaskClass) {
        NSLog(@"[TKCapture] ✓ TTHttpTask class EXISTS");

        // 打印所有实例方法
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(ttHttpTaskClass, &methodCount);
        NSLog(@"[TKCapture] TTHttpTask has %u methods:", methodCount);

        for (unsigned int i = 0; i < methodCount; i++) {
            SEL selector = method_getName(methods[i]);
            NSString *methodName = NSStringFromSelector(selector);

            // 只打印包含 request, resume, send, start 的方法
            if ([methodName.lowercaseString containsString:@"request"] ||
                [methodName.lowercaseString containsString:@"resume"] ||
                [methodName.lowercaseString containsString:@"send"] ||
                [methodName.lowercaseString containsString:@"start"]) {
                NSLog(@"[TKCapture]   - %@", methodName);
            }
        }

        if (methods) free(methods);
    } else {
        NSLog(@"[TKCapture] ✗ TTHttpTask class NOT FOUND");

        // 搜索可能的替代类名
        NSLog(@"[TKCapture] Searching for alternative classes...");

        unsigned int classCount = 0;
        Class *classes = objc_copyClassList(&classCount);

        for (unsigned int i = 0; i < classCount; i++) {
            const char *className = class_getName(classes[i]);
            NSString *name = [NSString stringWithUTF8String:className];

            // 查找包含 Http, Network, Request 的类
            if ([name containsString:@"Http"] ||
                [name containsString:@"Network"] ||
                [name containsString:@"Request"]) {

                // 排除系统类
                if (![name hasPrefix:@"NS"] &&
                    ![name hasPrefix:@"UI"] &&
                    ![name hasPrefix:@"CF"]) {
                    NSLog(@"[TKCapture]   Found: %@", name);
                }
            }
        }

        if (classes) free(classes);
    }

    // 2. 验证 TTHttpResponseChromium 类
    Class ttHttpResponseClass = objc_getClass("TTHttpResponseChromium");
    if (ttHttpResponseClass) {
        NSLog(@"[TKCapture] ✓ TTHttpResponseChromium class EXISTS");

        // 打印所有 ivar
        unsigned int ivarCount = 0;
        Ivar *ivars = class_copyIvarList(ttHttpResponseClass, &ivarCount);
        NSLog(@"[TKCapture] TTHttpResponseChromium has %u ivars:", ivarCount);

        for (unsigned int i = 0; i < ivarCount; i++) {
            Ivar ivar = ivars[i];
            const char *ivarName = ivar_getName(ivar);
            const char *ivarType = ivar_getTypeEncoding(ivar);
            NSLog(@"[TKCapture]   - %s (type: %s)", ivarName, ivarType);
        }

        if (ivars) free(ivars);
    }

    NSLog(@"[TKCapture] ==================== END DEBUG ====================");
}
