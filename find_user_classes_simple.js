console.log('[*] 枚举所有User相关类...\n');

setTimeout(function() {
    var found = [];
    for (var className in ObjC.classes) {
        var lower = className.toLowerCase();
        if (lower.indexOf('user') >= 0 && lower.indexOf('default') < 0) {
            found.push(className);
        }
    }
    
    console.log('找到 ' + found.length + ' 个User类：');
    found.slice(0, 100).forEach(function(name) {
        console.log('  - ' + name);
    });
}, 2000);
