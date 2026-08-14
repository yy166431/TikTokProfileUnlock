#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 稳定性探针: 只 attach, 完全不 hook, 每2秒报活一次, 看 TikTok 会不会自己崩
# 用来区分: hook导致崩 vs 反调试检测attach导致崩
import sys, time, frida

DEVICE = "192.168.9.102:27042"

JS = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
// 完全不 hook, 只每2秒报一次活, 证明进程还在
var n = 0;
var timer = setInterval(function(){
    n++;
    log('[alive] tick ' + n + '  (只attach未hook)');
    if (n >= 30){ clearInterval(timer); log('[done] 30次心跳完成, 进程稳定'); }
}, 2000);
log('[start] 纯attach探针, 不做任何hook');
"""

def on_message(msg, data):
    if msg.get('type') == 'send':
        print(msg['payload'].get('m'), flush=True)
    elif msg.get('type') == 'error':
        print('[JS-ERR]', msg.get('description'), flush=True)

def on_detached(reason):
    print('[!!!] session DETACHED, reason =', reason, flush=True)

dm = frida.get_device_manager()
dev = dm.add_remote_device(DEVICE)
pid = None
for p in dev.enumerate_processes():
    if p.name in ('TikTok','Aweme'): pid = p.pid; break
if not pid:
    print('[!] TikTok 没运行'); sys.exit(1)
print('[+] attach pid=%d (纯探针)' % pid, flush=True)
sess = dev.attach(pid)
sess.on('detached', on_detached)
scr = sess.create_script(JS)
scr.on('message', on_message)
scr.load()
time.sleep(65)
print('[*] 探针结束', flush=True)
