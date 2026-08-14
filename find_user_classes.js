console.log('[*] 枚举所有包含 User/Profile 的类...\n');

if (ObjC.available) {
    var userClasses = [];
    var profileClasses = [];
    
    for (var className in ObjC.classes) {
        var lower = className.toLowerCase();
        if (lower.indexOf('user') >= 0 && lower.indexOf('default') < 0) {
            userClasses.push(className);
        }
        if (lower.indexOf('profile') >= 0) {
            profileClasses.push(className);
        }
    }
    
    console.log('=== User 类 (' + userClasses.length + ') ===');
    userClasses.slice(0, 100).forEach(function(name) {
        console.log(name);
    });
    
    console.log('\n=== Profile 类 (' + profileClasses.length + ') ===');
    profileClasses.slice(0, 100).forEach(function(name) {
        console.log(name);
    });
}
