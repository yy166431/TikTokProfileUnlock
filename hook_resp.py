#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 钩 TTNetworkManagerChromium handleResponsePreProcessing:data:error:request:
# data = 已解密+解压的明文, request 带 URL. 只钩1个方法, 不detach(避免PAC还原崩)
import sys, time, frida, signal

DEVICE = "192.168.9.102:27042"

JS = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
function hit(m){ send({t:'hit', m:m}); }

function urlOfRequest(p){
    try {
        if (!p || p.isNull()) return null;
        var o = new ObjC.Object(p);
        // request 对象: 尝试 .URL().absoluteString() 或 .tspk_util_url()
        var cand = ['URL','tspk_util_url','requestUrl','url'];
        for (var i=0;i<cand.length;i++){
            try {
                if (o.respondsToSelector_(ObjC.selector(cand[i]))){
                    var u = o[cand[i]]();
                    if (u){
                        var s = u.toString();
                        if (s.indexOf('http')===0) return s;
                        // 可能是 NSURL
                        try { var a = u.absoluteString(); if(a) return a.toString(); } catch(e){}
                    }
                }
            } catch(e){}
        }
    } catch(e){}
    return null;
}

function dataToStr(p){
    try {
        if (!p || p.isNull()) return null;
        var o = new ObjC.Object(p);
        if (o.$className.indexOf('Data') < 0) return null;
        var len = o.length().valueOf();
        if (len <= 0 || len > 200000) return '[data len=' + len + ' 太大跳过]';
        var bytes = o.bytes();
        var s = bytes.readUtf8String(len);
        return s;
    } catch(e){ return null; }
}

setTimeout(function(){
    var C = ObjC.classes.TTNetworkManagerChromium;
    if (!C){ log('[!] Chromium class missing'); return; }
    var sel = null;
    C.$ownMethods.forEach(function(s){
        if (s.indexOf('handleResponsePreProcessing') >= 0 && s.indexOf('data:') >= 0){ sel = s; }
    });
    if (!sel){ log('[!] handleResponsePreProcessing not found'); return; }
    log('[target] ' + sel);
    // handleResponsePreProcessing_:data:error:request:preprocessor:...
    // args: 0=self 1=sel 2=response 3=data 4=error 5=request ...
    try {
        Interceptor.attach(C[sel].implementation, {
            onEnter: function(args){
                try {
                    var url = urlOfRequest(args[5]) || urlOfRequest(args[2]) || '(url?)';
                    var isProfile = /profile\/self|\/user\/profile|aweme\/v1\/user/i.test(url);
                    if (isProfile){
                        var body = dataToStr(args[3]);
                        hit('[★PROFILE/SELF★]\nURL: ' + url + '\n--- BODY ---\n' + (body||'(no data)') + '\n=========');
                    } else {
                        log('[resp] ' + url.split('?')[0]);
                    }
                } catch(e){ log('[onEnter-err] '+e); }
            }
        });
        log('[OK] hooked, 现在点个人主页/下拉刷新, 盯 ★PROFILE/SELF★');
    } catch(e){ log('[hook-err] '+e); }
}, 400);
"""

hits = []
def on_message(msg, data):
    if msg.get('type') == 'send':
        m = msg['payload'].get('m')
        print(m, flush=True)
    elif msg.get('type') == 'error':
        print('[JS-ERR]', msg.get('description'), flush=True)

def main():
    dm = frida.get_device_manager()
    dev = dm.add_remote_device(DEVICE)
    pid = None
    for p in dev.enumerate_processes():
        if p.name in ('TikTok','Aweme'): pid = p.pid; break
    if not pid:
        print('[!] TikTok 没运行', flush=True); return
    print('[+] attach pid=%d' % pid, flush=True)
    sess = dev.attach(pid)
    scr = sess.create_script(JS)
    scr.on('message', on_message)
    scr.load()
    run = int(sys.argv[1]) if len(sys.argv) > 1 else 180
    end = time.time() + run
    while time.time() < end:
        time.sleep(1)
    # 关键: 不调用 detach/unload, 直接退出进程, 避免 PAC 还原 hook 崩 TikTok
    print('[*] 结束(不detach, 保护进程)', flush=True)
    import os
    os._exit(0)

if __name__ == '__main__':
    main()
