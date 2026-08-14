#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 纯 frida 抓 TikTok 网络请求, 重点抓 /tiktok/user/profile/self
import sys, time, frida

DEVICE = "192.168.9.102:27042"
TARGET = "com.zhiliaoapp.musically"

JS = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
function hit(m){ send({t:'hit', m:m}); }

// ---- 抓 NSURL / NSURLRequest 全量 ----
function safeStr(p){
    try { var o = new ObjC.Object(p); return o.toString(); } catch(e){ return null; }
}

// A) hook TTNetworkManager 系列
function hookTTNet(){
    var TTN = ObjC.classes.TTNetworkManager;
    if (!TTN){ log('[A] TTNetworkManager missing'); return 0; }
    var hooked = 0;
    var methods = TTN.$ownMethods;
    methods.forEach(function(sel){
        var low = sel.toLowerCase();
        if (low.indexOf('url') >= 0 || low.indexOf('request') >= 0){
            try {
                Interceptor.attach(TTN[sel].implementation, {
                    onEnter: function(args){
                        for (var i=2; i<7; i++){
                            var s = safeStr(args[i]);
                            if (s && s.indexOf('http') === 0 && s.length < 500){
                                report('TTNet.'+sel, s);
                                break;
                            }
                        }
                    }
                });
                hooked++;
            } catch(e){}
        }
    });
    log('[A] TTNetworkManager hooked = ' + hooked);
    return hooked;
}

// B) hook NSURLRequest initWithURL / requestWithURL (兜底)
function hookNSURL(){
    try {
        var R = ObjC.classes.NSURLRequest;
        ['requestWithURL:','requestWithURL:cachePolicy:timeoutInterval:'].forEach(function(sel){
            if (R[sel]){
                Interceptor.attach(R[sel].implementation, {
                    onEnter: function(args){
                        var s = safeStr(args[2]);
                        if (s && s.indexOf('http')===0) report('NSURLRequest', s);
                    }
                });
            }
        });
        var M = ObjC.classes.NSMutableURLRequest;
        if (M && M['setURL:']){
            Interceptor.attach(M['setURL:'].implementation, {
                onEnter: function(args){
                    var s = safeStr(args[2]);
                    if (s && s.indexOf('http')===0) report('NSMutableURLRequest.setURL', s);
                }
            });
        }
        log('[B] NSURLRequest hooked');
    } catch(e){ log('[B-ERR] '+e); }
}

// C) 最底层兜底: CFURL / NSURLSession dataTaskWithRequest
function hookSession(){
    try {
        var S = ObjC.classes.NSURLSession;
        var sels = S.$ownMethods.filter(function(s){ return s.indexOf('dataTaskWith')>=0 || s.indexOf('taskWith')>=0; });
        sels.forEach(function(sel){
            try {
                Interceptor.attach(S[sel].implementation, {
                    onEnter: function(args){
                        var s = safeStr(args[2]);
                        if (s && s.indexOf('http')<0){
                            // args[2] 可能是 request 对象, 取它的 URL
                            try { s = new ObjC.Object(args[2]).URL().toString(); } catch(e){}
                        }
                        if (s && s.indexOf('http')===0) report('NSURLSession.'+sel, s);
                    }
                });
            } catch(e){}
        });
        log('[C] NSURLSession hooked = ' + sels.length);
    } catch(e){ log('[C-ERR] '+e); }
}

var seen = {};
function report(where, url){
    // 只保留 path, 去掉超长 query 便于看
    var shortu = url.split('?')[0];
    var key = where + '|' + shortu;
    var isProfile = url.toLowerCase().indexOf('profile') >= 0 || url.indexOf('/user/') >= 0;
    if (isProfile){
        hit('[★PROFILE★] ' + where + ' => ' + url);
    } else {
        if (seen[key]) return;   // 非profile的去重, 避免刷屏
        seen[key] = 1;
        log('[req] ' + where + ' => ' + shortu);
    }
}

setTimeout(function(){
    hookTTNet();
    hookNSURL();
    hookSession();
    log('[READY] 抓包已启动! 现在去刷抖音, 然后点"我"进个人主页, 盯 ★PROFILE★');
}, 300);
"""

def on_message(msg, data):
    if msg.get('type') == 'send':
        p = msg['payload']
        if isinstance(p, dict):
            print(p.get('m'), flush=True)
        else:
            print(p, flush=True)
    elif msg.get('type') == 'error':
        print('[JS-ERROR]', msg.get('description'), flush=True)

def main():
    dm = frida.get_device_manager()
    dev = dm.add_remote_device(DEVICE)

    pid = None
    for p in dev.enumerate_processes():
        if p.name in ('TikTok', 'Aweme'):
            pid = p.pid; break

    if pid:
        print('[+] TikTok 已在运行, attach pid=%d' % pid, flush=True)
        sess = dev.attach(pid)
    else:
        print('[*] TikTok 没运行, spawn 启动...', flush=True)
        pid = dev.spawn([TARGET])
        sess = dev.attach(pid)
        dev.resume(pid)
        print('[+] spawn pid=%d 已恢复' % pid, flush=True)

    scr = sess.create_script(JS)
    scr.on('message', on_message)
    scr.load()
    print('[+] 脚本加载完成, 监控中...', flush=True)
    # 后台运行不能靠 stdin, 直接跑固定时长
    run_secs = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    end = time.time() + run_secs
    while time.time() < end:
        time.sleep(1)
    print('[*] 监控结束', flush=True)

if __name__ == '__main__':
    main()
