#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 只列出 TTNetworkManager 方法名, 不做任何 hook, 绝对不会崩
import sys, time, frida

DEVICE = "192.168.9.102:27042"

JS = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
setTimeout(function(){
    try {
        var names = ['TTNetworkManager','TTHttpTask','TTHTTPTask',
                     'TTDefaultHTTPRequestSerializer','TTHTTPRequestSerializerBase',
                     'TTNetworkManagerChromium','TTHttpResponse','TTResponse'];
        names.forEach(function(n){
            var c = ObjC.classes[n];
            log('[CLASS] ' + n + ' => ' + (c ? 'PRESENT' : 'missing'));
        });
        var TTN = ObjC.classes.TTNetworkManager;
        if (TTN){
            log('=== TTNetworkManager own methods ===');
            TTN.$ownMethods.forEach(function(s){ log('  ' + s); });
        }
        // 找所有类名带 Network / HTTP / Request 的
        log('=== classes matching Network/HTTP ===');
        var cnt = 0;
        for (var cn in ObjC.classes){
            if (/TTNetwork|TTHTTP|TTHttp|TTRequest/.test(cn)){
                log('  ' + cn); cnt++;
                if (cnt > 40) break;
            }
        }
    } catch(e){ log('[ERR] ' + e); }
}, 300);
"""

def on_message(msg, data):
    if msg.get('type') == 'send':
        print(msg['payload'].get('m'), flush=True)
    elif msg.get('type') == 'error':
        print('[JS-ERROR]', msg.get('description'), flush=True)

dm = frida.get_device_manager()
dev = dm.add_remote_device(DEVICE)
pid = None
for p in dev.enumerate_processes():
    if p.name in ('TikTok','Aweme'): pid = p.pid; break
if not pid:
    print('[!] TikTok 没运行'); sys.exit(1)
print('[+] attach pid=%d (只读, 不hook)' % pid, flush=True)
sess = dev.attach(pid)
scr = sess.create_script(JS)
scr.on('message', on_message)
scr.load()
time.sleep(4)
print('[*] done', flush=True)
