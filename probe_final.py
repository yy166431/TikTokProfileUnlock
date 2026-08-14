#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 零枚举: 写死候选类名, 直接访问确认存在, 并列出目标selector真实签名
import sys, time, frida, json

DEVICE = "192.168.9.102:27042"

RESP_CLASSES = [
    "TTHTTPBinaryResponseSerializerBase", "AWEBinaryResponseSerializer",
    "AWEBinaryResponseSerializerForJSON", "AWEFeedPbResponseSerializer",
    "BDXBridgePbResponseSerializer", "HTSLivePBResponseSerializer",
    "TIMClientTTNetworkImpResponseSerializer", "TTIMStreakPBResponseSerializer",
    "TTKECProtobufResponseSerializer", "TTKFeedBasePbResponseSerializer",
    "TTKLandscapePostPbResponseSerializer", "TTKLanscapeFeedPbResponseSerializer",
    "TTKPaidContentPbBaseResponseSerializer", "TikTokKidsFeedPbResponseSerializer",
]
REQ_CLASSES = [
    "TTHTTPRequestSerializerBaseChromium", "TTHTTPRequestSerializerChromium",
    "TTHTTPRequestSerializer",
]

JS_TMPL = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
var RESP = __RESP__;
var REQ = __REQ__;
setTimeout(function(){
    log('=== RESPONSE serializers ===');
    RESP.forEach(function(cn){
        var C = ObjC.classes[cn];
        if (!C){ return; }
        var found = [];
        C.$ownMethods.forEach(function(s){
            if (s.indexOf('responseObjectForResponse:data:') >= 0) found.push(s);
        });
        log('[EXIST] ' + cn + (found.length ? ('  SEL='+found.join('|')) : '  (无data:selector,可能继承基类)'));
    });
    log('=== REQUEST serializers ===');
    REQ.forEach(function(cn){
        var C = ObjC.classes[cn];
        if (!C){ return; }
        var found = [];
        C.$ownMethods.forEach(function(s){
            if (s.indexOf('URLRequestWith') >= 0) found.push(s);
        });
        log('[EXIST] ' + cn);
        found.forEach(function(s){ log('    ' + s); });
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
js = JS_TMPL.replace('__RESP__', json.dumps(RESP_CLASSES)).replace('__REQ__', json.dumps(REQ_CLASSES))
scr = sess.create_script(js)
scr.on('message', on_message)
scr.load()
time.sleep(6)
print('[*] done', flush=True)
import os; os._exit(0)
