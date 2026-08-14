#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 监控 TikTok: attach 后确认我们的 dylib 加载 + hook TTNetworkManager 抓请求
import sys, time, frida

DEVICE = "192.168.9.102:27042"
TARGET = "com.zhiliaoapp.musically"

JS = r"""
'use strict';

function log(m){ send({t:'log', m:m}); }

// 1) 确认我们的 dylib 是否已加载
try {
    var mods = Process.enumerateModules();
    var found = false;
    mods.forEach(function(m){
        if (m.name.toLowerCase().indexOf('profileunlock') >= 0 ||
            m.name.toLowerCase().indexOf('tiktokprofile') >= 0) {
            log('[DYLIB] LOADED -> ' + m.name + ' @ ' + m.base + ' size=' + m.size);
            found = true;
        }
    });
    if (!found) log('[DYLIB] *** NOT LOADED *** (我们的dylib没进来!)');
} catch(e){ log('[DYLIB-ERR] ' + e); }

// 2) 列出 TTNetworkManager / TTHttpTask 相关类
try {
    var names = ['TTNetworkManager','TTHttpTask','TTDefaultHTTPRequestSerializer',
                 'TTHTTPRequestSerializerBase','TTHttpResponse'];
    names.forEach(function(n){
        var c = ObjC.classes[n];
        log('[CLASS] ' + n + ' => ' + (c ? 'PRESENT' : 'missing'));
    });
} catch(e){ log('[CLASS-ERR] ' + e); }

// 3) hook TTNetworkManager 的请求方法, 打印所有 URL (看能不能抓到 profile/self)
function hookTTNet(){
    var TTN = ObjC.classes.TTNetworkManager;
    if (!TTN) { log('[HOOK] TTNetworkManager 不存在, 跳过'); return; }
    var methods = TTN.$ownMethods;
    var hooked = 0;
    methods.forEach(function(sel){
        if (sel.indexOf('URL:') >= 0 || sel.indexOf('requestWith') >= 0 ||
            sel.indexOf('requestForBinary') >= 0 || sel.indexOf('URLRequest') >= 0) {
            try {
                var impl = TTN[sel];
                Interceptor.attach(impl.implementation, {
                    onEnter: function(args){
                        try {
                            // 参数里找 URL 字符串
                            for (var i=2; i<6; i++){
                                try {
                                    var a = new ObjC.Object(args[i]);
                                    var s = a.toString();
                                    if (s && s.indexOf('http') === 0 && s.length < 400){
                                        log('[REQ ' + sel + '] ' + s);
                                        break;
                                    }
                                } catch(e2){}
                            }
                        } catch(e){}
                    }
                });
                hooked++;
            } catch(e){ log('[HOOK-ERR ' + sel + '] ' + e); }
        }
    });
    log('[HOOK] TTNetworkManager hooked methods = ' + hooked);
}
setTimeout(hookTTNet, 500);
log('[READY] 监控启动, 现在去刷抖音 + 点个人主页');
"""

def on_message(msg, data):
    if msg.get('type') == 'send':
        p = msg['payload']
        if isinstance(p, dict) and p.get('t') == 'log':
            print(p['m'], flush=True)
        else:
            print(p, flush=True)
    elif msg.get('type') == 'error':
        print('[JS-ERROR]', msg.get('description'), flush=True)

def main():
    dm = frida.get_device_manager()
    dev = dm.add_remote_device(DEVICE)
    # 等 TikTok 起来
    pid = None
    print('[*] 等待 TikTok 进程...', flush=True)
    for _ in range(120):
        for a in dev.enumerate_processes():
            if a.name == 'TikTok' or a.name == 'Aweme':
                pid = a.pid; break
        if pid: break
        time.sleep(1)
    if not pid:
        print('[!] TikTok 没在运行, 请先在手机上打开它', flush=True); return
    print('[+] attach pid=', pid, flush=True)
    sess = dev.attach(pid)
    scr = sess.create_script(JS)
    scr.on('message', on_message)
    scr.load()
    print('[+] 脚本已加载, 监控中... Ctrl+C 退出', flush=True)
    sys.stdin.read()

if __name__ == '__main__':
    main()
