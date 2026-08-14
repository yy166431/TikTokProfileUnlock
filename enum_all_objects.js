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
