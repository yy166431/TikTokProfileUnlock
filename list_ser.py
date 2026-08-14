#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 纯只读: 只列 serializer 类名和方法, 一个 Interceptor 都不挂
import sys, time, frida

DEVICE = "192.168.9.102:27042"

JS = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
setTimeout(function(){
    try {
        var targets = [];
        for (var cn in ObjC.classes){
            if (/ResponseSerializer|JSONResponseSerializer|BinaryResponseSerializer/.test(cn))
                targets.push(cn);
        }
        log('[serializer classes] count=' + targets.length);
        targets.forEach(function(cn){ log('  CLASS ' + cn); });

        // 列每个类里 responseObjectForResponse 相关方法
        targets.forEach(function(cn){
            var C = ObjC.classes[cn];
            if (!C) return;
            C.$ownMethods.forEach(function(s){
                if (s.indexOf('responseObjectForResponse') >= 0)
                    log('  METHOD ' + cn + ' -> ' + s);
            });
        });
        log('[done-listing] 只读完成, 未挂任何hook');
    } catch(e){ log('[ERR] '+e); }
}, 400);
"""

def on_message(msg, data):
    if msg.get('type') == 'send':
        print(msg['payload'].get('m'), flush=True)
    elif msg.get('type') == 'error':
        print('[JS-ERR]', msg.get('description'), flush=True)

def on_detached(reason):
    print('[!!! DETACHED]', reason, flush=True)

dm = frida.get_device_manager()
dev = dm.add_remote_device(DEVICE)
pid = None
for p in dev.enumerate_processes():
    if p.name in ('TikTok','Aweme'): pid = p.pid; break
if not pid:
    print('[!] TikTok 没运行'); sys.exit(1)
print('[+] attach pid=%d (纯只读)' % pid, flush=True)
sess = dev.attach(pid)
sess.on('detached', on_detached)
scr = sess.create_script(JS)
scr.on('message', on_message)
scr.load()
time.sleep(8)
print('[*] done', flush=True)
import os; os._exit(0)
