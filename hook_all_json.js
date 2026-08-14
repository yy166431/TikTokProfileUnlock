console.log('[*] Hook 所有 JSON 解析...\n');

if (ObjC.available) {
    var NSJSONSerialization = ObjC.classes.NSJSONSerialization;
    var count = 0;
    
    Interceptor.attach(NSJSONSerialization['+ JSONObjectWithData:options:error:'].implementation, {
        onLeave: function(retval) {
            count++;
            if (count % 50 == 0) {
                console.log('[JSON解析] 已拦截 ' + count + ' 次');
            }
            
            if (retval.isNull()) return;
            try {
                var obj = new ObjC.Object(retval);
                var str = obj.toString();
                
                // 检查是否包含用户相关字段
                var keywords = ['sec_uid', 'follower', 'unique_id', 'aweme_count', 'nickname', 'avatar'];
                for (var i = 0; i < keywords.length; i++) {
                    if (str.indexOf(keywords[i]) >= 0) {
                        console.log('\n[★JSON命中★] 关键词: ' + keywords[i] + ', 长度: ' + str.length);
                        console.log(str.substring(0, 1000));
                        console.log('---\n');
                        break;
                    }
                }
            } catch(e) {}
        }
    });
    
    console.log('[+] NSJSONSerialization 已 Hook');
    console.log('[*] 请在设备上点击"我"进入个人主页...\n');
}
