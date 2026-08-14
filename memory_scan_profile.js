// memory_scan_profile.js
// 扫描 TikTok 进程内存找 profile/self 数据

function scanForProfile() {
    console.log('[*] 开始扫描内存...');

    // 关键字段模式
    const patterns = [
        'sec_uid',
        'unique_id',
        'follower_count',
        'following_count',
        'aweme_count',
        'profile/self'
    ];

    // 扫描主二进制和 MusicallyCore
    Process.enumerateModules().forEach(function(mod) {
        if (mod.name.indexOf('TikTok') >= 0 || mod.name.indexOf('MusicallyCore') >= 0) {
            console.log('[+] 扫描模块: ' + mod.name);

            patterns.forEach(function(pattern) {
                Memory.scanSync(mod.base, mod.size, pattern).forEach(function(match) {
                    // 读取匹配位置前后 2KB 数据
                    try {
                        var data = Memory.readByteArray(match.address.sub(512), 2048);
                        var str = '';
                        var bytes = new Uint8Array(data);
                        for (var i = 0; i < bytes.length; i++) {
                            if (bytes[i] >= 32 && bytes[i] <= 126) {
                                str += String.fromCharCode(bytes[i]);
                            } else {
                                str += '.';
                            }
                        }

                        // 检查是否包含多个特征字段
                        var score = 0;
                        patterns.forEach(function(p) {
                            if (str.indexOf(p) >= 0) score++;
                        });

                        if (score >= 3) {
                            console.log('[!!!] 找到疑似 profile 数据:');
                            console.log('地址: ' + match.address);
                            console.log('内容:\n' + str.substring(0, 1000));
                            send({type: 'profile', data: str, address: match.address.toString()});
                        }
                    } catch(e) {}
                });
            });
        }
    });
}

// 延迟执行，等数据加载完
setTimeout(scanForProfile, 5000);
setInterval(scanForProfile, 30000);  // 每30秒扫一次
