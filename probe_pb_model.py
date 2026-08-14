#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 写死类名 GetUserProfileSelfResponse, 列全部方法+父类链, 找反序列化入口
import sys, time, frida

DEVICE = "192.168.9.102:27042"
CLS = "GetUserProfileSelfResponse"

JS_TMPL = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
var CLS = "__CLS__";
setTimeout(function(){
    var C = ObjC.classes[CLS];
    if (!C){ log('[!] 不存在 '+CLS); return; }
    // 父类链
    var chain = [];
    var cur = C;
    for (var i=0;i<8 && cur;i++){
        chain.push(cur.$className);
        cur = cur.$superClass;
    }
    log('[super-chain] ' + chain.join(' -> '));

    // 自己的方法(全列,类方法+可能的parse)
    log('[ownMethods]');
    C.$ownMethods.forEach(function(s){ log('   ' + s); });

    // 父类若是protobuf基类, 列父类的class方法(+parseFromData:等)
    var sup = C.$superClass;
    if (sup){
        log('[super ' + sup.$className + ' ownMethods (parse/data related)]');
        try {
            sup.$ownMethods.forEach(function(s){
                if (/parse|Data|data:|decode|init|merge|message/i.test(s))
                    log('   ' + s);
            });
        } catch(e){ log('[super-err]'+e); }
    }
    log('[done]');
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
print('[+] attach pid=%d' % pid, flush=True)
sess = dev.attach(pid)
sess.on('detached', on_detached)
scr = sess.create_script(JS_TMPL.replace('__CLS__', CLS))
scr.on('message', on_message)
scr.load()
time.sleep(6)
print('[*] done', flush=True)
import os; os._exit(0)
