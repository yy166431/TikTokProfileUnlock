#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 外科手术版: 只 hook TTNetworkManager 的 4 个请求入口, 只读 arg2(URL), 绝不崩
import sys, time, frida

DEVICE = "192.168.9.102:27042"

JS = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
function hit(m){ send({t:'hit', m:m}); }

function readURL(p){
    try {
        if (p.isNull()) return null;
        var o = new ObjC.Object(p);
        var cls = o.$className;
        // 只接受 NSString / NSURL, 其它一律不碰
        if (cls.indexOf('String') >= 0 || cls.indexOf('URL') >= 0 || cls.indexOf('CFString') >= 0){
            var s = o.toString();
            if (s && s.indexOf('http') === 0) return s;
        }
    } catch(e){}
    return null;
}

function report(where, url){
    var low = url.toLowerCase();
    if (low.indexOf('profile') >= 0 || url.indexOf('/user/') >= 0 || low.indexOf('/self/') >= 0){
        hit('[PROFILE] ' + where + '\n           ' + url);
    } else {
        log('[req] ' + where + ' => ' + url.split('?')[0]);
    }
}

setTimeout(function(){
    var TTN = ObjC.classes.TTNetworkManager;
    if (!TTN){ log('[!] TTNetworkManager missing'); return; }

    var targets = [];
    TTN.$ownMethods.forEach(function(sel){
        if (sel.indexOf('requestForJSONWithURL') >= 0 ||
            sel.indexOf('requestForBinaryWithURL') >= 0 ||
            sel.indexOf('requestWithURL:method:params:callback:') >= 0 ||
            sel.indexOf('bdxbridge_requestWithURL:') >= 0 ||
            sel.indexOf('synchronizedRequstForURL:') >= 0 ||
            sel.indexOf('requestForWebviewCommon:mainDocURL:') >= 0){
            targets.push(sel);
        }
    });

    var n = 0;
    targets.forEach(function(sel){
        try {
            Interceptor.attach(TTN[sel].implementation, {
                onEnter: function(args){
                    var u = readURL(args[2]);
                    if (u) report(sel, u);
                }
            });
            n++;
            log('[hook] ' + sel);
        } catch(e){ log('[hook-err] ' + sel + ' : ' + e); }
    });
    log('[READY] 精准hook ' + n + ' 个入口, 现在点"我"进个人主页, 盯 [PROFILE]');
}, 400);
"""

def on_message(msg, data):
    if msg.get('type') == 'send':
        print(msg['payload'].get('m'), flush=True)
    elif msg.get('type') == 'error':
        print('[JS-ERROR]', msg.get('description'), flush=True)

def main():
    dm = frida.get_device_manager()
    dev = dm.add_remote_device(DEVICE)
    pid = None
    for p in dev.enumerate_processes():
        if p.name in ('TikTok','Aweme'): pid = p.pid; break
    if not pid:
        print('[!] TikTok 没运行, 请先打开', flush=True); return
    print('[+] attach pid=%d' % pid, flush=True)
    sess = dev.attach(pid)
    scr = sess.create_script(JS)
    scr.on('message', on_message)
    scr.load()
    run = int(sys.argv[1]) if len(sys.argv) > 1 else 240
    end = time.time() + run
    while time.time() < end:
        time.sleep(1)
    print('[*] 结束', flush=True)

if __name__ == '__main__':
    main()
