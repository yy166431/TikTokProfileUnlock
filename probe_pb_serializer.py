#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 不遍历ObjC.classes! 写死一批候选类名, 直接访问(不存在返回undefined,安全)
# 对存在的类只调它自己的$ownMethods列方法
import sys, time, frida

DEVICE = "192.168.9.102:27042"

# 候选序列化器/反序列化类名 (protobuf/binary/model)
CANDS = [
    "TTHTTPJSONResponseSerializerBaseChromium",
    "TTHTTPBinaryResponseSerializerBaseChromium",
    "TTHTTPProtobufResponseSerializer",
    "TTHTTPPBResponseSerializer",
    "TTHTTPResponseSerializerChromium",
    "TTHTTPResponseSerializer",
    "AWEHTTPResponseSerializer",
    "AWEProtobufResponseSerializer",
    "BDNetworkResponseSerializer",
    "TTNetRPCResponseSerializer",
    "TTHTTPModelResponseSerializer",
    "AWEHTTPBinaryResponseSerializer",
    "TTHTTPJSONResponseSerializerChromium",
    "TTHTTPJSONResponseSerializer",
    "TTResponseModelSerializer",
    "AWEAwemeResponseModelSerializer",
    "GetUserProfileSelfResponse",
    "TTHTTPRequestSerializer",
]

JS_TMPL = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
var CANDS = __CANDS__;
setTimeout(function(){
    CANDS.forEach(function(cn){
        var C = ObjC.classes[cn];   // 直接取, 不遍历
        if (!C){ return; }
        log('[EXIST] ' + cn);
        try {
            C.$ownMethods.forEach(function(s){
                if (s.indexOf('esponse') >= 0 || s.indexOf('data:') >= 0 ||
                    s.indexOf('serialize') >= 0 || s.indexOf('parse') >= 0 ||
                    s.indexOf('decode') >= 0 || s.indexOf('Obj') >= 0)
                    log('    M ' + cn + ' -> ' + s);
            });
        } catch(e){ log('  [own-err] '+cn+' '+e); }
    });
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

import json
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
scr = sess.create_script(JS_TMPL.replace('__CANDS__', json.dumps(CANDS)))
scr.on('message', on_message)
scr.load()
time.sleep(6)
print('[*] done', flush=True)
import os; os._exit(0)
