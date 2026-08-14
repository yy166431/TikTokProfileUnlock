#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 找响应层: TTHttpResponse / ResponseSerializer 的方法, 以及能拿到 URL+data 的点
import sys, time, frida

DEVICE = "192.168.9.102:27042"

JS = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
setTimeout(function(){
    try {
        var classes = ['TTHttpResponse','TTDefaultHTTPRequestSerializer',
                       'TTHTTPRequestSerializerBase','TTHTTPJSONResponseSerializer',
                       'TTHTTPBinaryResponseSerializer','TTNetworkManagerChromium'];
        classes.forEach(function(cn){
            var c = ObjC.classes[cn];
            if (!c){ log('[MISSING] ' + cn); return; }
            log('===== ' + cn + ' =====');
            c.$ownMethods.forEach(function(s){
                // 只列可能含 url/data/response/header 的
                var l = s.toLowerCase();
                if (l.indexOf('url')>=0 || l.indexOf('data')>=0 || l.indexOf('json')>=0 ||
                    l.indexOf('response')>=0 || l.indexOf('header')>=0 || l.indexOf('body')>=0 ||
                    l.indexOf('init')>=0 || l.indexOf('serializ')>=0){
                    log('  ' + s);
                }
            });
        });
        // 找所有类名带 ResponseSerializer 的
        log('===== classes matching ResponseSerializer =====');
        var cnt=0;
        for (var cn in ObjC.classes){
            if (/ResponseSerializer|TTHttpResponse|ChromiumResponse/.test(cn)){
                log('  ' + cn); if(++cnt>30) break;
            }
        }
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
