#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 找 TikTok 真正的网络栈: 列 module + 找 SSL_write/boringssl + cronet 符号
import sys, time, frida

DEVICE = "192.168.9.102:27042"

JS = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
setTimeout(function(){
    try {
        log('=== modules (含 net/ssl/cronet/boring/tt) ===');
        Process.enumerateModules().forEach(function(m){
            var n = m.name.toLowerCase();
            if (n.indexOf('ssl')>=0 || n.indexOf('cronet')>=0 || n.indexOf('boring')>=0 ||
                n.indexOf('net')>=0 || n.indexOf('tt')>=0 || n.indexOf('quic')>=0 ||
                n.indexOf('crypto')>=0 || m.name.indexOf('TikTok')>=0){
                log('  ' + m.name + '  base=' + m.base + ' sz=' + m.size);
            }
        });
        log('=== 找 SSL_write / SSL_read 导出 ===');
        ['SSL_write','SSL_read','SSL_get_servername'].forEach(function(fn){
            var p = Module.findExportByName(null, fn);
            log('  ' + fn + ' => ' + (p ? p : 'null'));
        });
    } catch(e){ log('[ERR] ' + e); }
}, 300);
"""

def on_message(msg, data):
    if msg.get('type') == 'send':
        print(msg['payload'].get('m'), flush=True)
    elif msg.get('type') == 'error':
        print('[JS-ERR]', msg.get('description'), flush=True)

dm = frida.get_device_manager()
dev = dm.add_remote_device(DEVICE)
pid = None
for p in dev.enumerate_processes():
    if p.name in ('TikTok','Aweme'): pid = p.pid; break
if not pid:
    print('[!] TikTok 没运行'); sys.exit(1)
print('[+] attach pid=%d (只读)' % pid, flush=True)
sess = dev.attach(pid)
scr = sess.create_script(JS)
scr.on('message', on_message)
scr.load()
time.sleep(4)
print('[*] done', flush=True)
