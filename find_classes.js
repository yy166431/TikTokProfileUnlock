console.log('[*] Enumerating ObjC classes for User/Profile...\n');

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

console.log('=== User Classes (' + userClasses.length + ') ===');
userClasses.slice(0, 50).forEach(function(name) {
    console.log(name);
});

console.log('\n=== Profile Classes (' + profileClasses.length + ') ===');
profileClasses.slice(0, 50).forEach(function(name) {
    console.log(name);
});

console.log('\n[*] Done! Total: ' + userClasses.length + ' User, ' + profileClasses.length + ' Profile');
