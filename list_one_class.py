#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 只对1个写死的类调 $ownMethods, 不遍历 ObjC.classes, 列出真实 selector
import sys, time, frida

DEVICE = "192.168.9.102:27042"
CLS = sys.argv[2] if len(sys.argv) > 2 else "TTHTTPJSONResponseSerializerBaseChromium"

JS_TMPL = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
var CLS = "__CLS__";
setTimeout(function(){
    try {
        var C = ObjC.classes[CLS];
        if (!C){ log('[!] class 不存在: ' + CLS); return; }
        log('[class] ' + CLS);
        var own = C.$ownMethods;   // 只对这一个类, 不遍历全部
        log('[ownMethods count] ' + own.length);
        own.forEach(function(s){
            if (s.indexOf('responseObject') >= 0 || s.indexOf('esponse') >= 0)
                log('  M ' + s);
        });
        log('[done]');
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
print('[+] attach pid=%d class=%s' % (pid, CLS), flush=True)
sess = dev.attach(pid)
sess.on('detached', on_detached)
scr = sess.create_script(JS_TMPL.replace('__CLS__', CLS))
scr.on('message', on_message)
scr.load()
time.sleep(6)
print('[*] done', flush=True)
import os; os._exit(0)
