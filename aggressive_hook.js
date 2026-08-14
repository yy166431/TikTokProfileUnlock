// Aggressive hook - catch ANY method containing user/profile keywords
console.log('[*] Starting aggressive method interception...\n');

var hookedMethods = 0;
var targets = ['user', 'profile', 'account', 'follower', 'following'];

// Hook NSJSONSerialization to catch ALL JSON parsing
if (ObjC.available) {
    var NSJSONSerialization = ObjC.classes.NSJSONSerialization;

    Interceptor.attach(NSJSONSerialization['+ JSONObjectWithData:options:error:'].implementation, {
        onEnter: function(args) {
            this.data = new ObjC.Object(args[2]);
        },
        onLeave: function(retval) {
            if (retval.isNull()) return;
            try {
                var result = new ObjC.Object(retval);
                var desc = result.toString();

                // Check if contains user-related keywords
                for (var i = 0; i < targets.length; i++) {
                    if (desc.toLowerCase().indexOf(targets[i]) >= 0) {
                        console.log('\n[JSON PARSE HIT] Length: ' + desc.length);
                        console.log(desc.substring(0, 2000));
                        console.log('---END---\n');
                        break;
                    }
                }
            } catch(e) {}
        }
    });

    console.log('[*] Hooked NSJSONSerialization - waiting for JSON parsing...');
    console.log('[*] Please navigate to profile page NOW!');
}
