#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 钩响应反序列化层 (serializer), 拿 profile/self 的明文数据
# responseObjectForResponse:jsonObj:...  和  responseObjectForResponse:data:...
# 结束用 os._exit 不 detach, 避免崩进程
import sys, time, frida

DEVICE = "192.168.9.102:27042"

JS = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
function hit(m){ send({t:'hit', m:m}); }

// 从 TTHttpResponse 里挖 URL
function urlOf(p){
    try {
        if (!p || p.isNull()) return null;
        var o = new ObjC.Object(p);
        // 直接 .URL
        var tries = ['URL','finalURL','tspk_util_url'];
        for (var i=0;i<tries.length;i++){
            try {
                if (o.respondsToSelector_(ObjC.selector(tries[i]))){
                    var u = o[tries[i]]();
                    if (u && !u.isNull()){
                        var s = u.toString();
                        if (s.indexOf('http')===0) return s;
                        try { var a = u.absoluteString(); if(a) return a.toString(); } catch(e){}
                    }
                }
            } catch(e){}
        }
        // .response -> NSHTTPURLResponse -> .URL
        try {
            if (o.respondsToSelector_(ObjC.selector('response'))){
                var r = o.response();
                if (r && !r.isNull()){
                    var ro = new ObjC.Object(r);
                    var u2 = ro.URL();
                    if (u2) return u2.absoluteString().toString();
                }
            }
        } catch(e){}
    } catch(e){}
    return null;
}

function dataStr(p){
    try {
        if (!p || p.isNull()) return null;
        var o = new ObjC.Object(p);
        var cls = o.$className || '';
        if (cls.indexOf('Data') >= 0){
            var len = o.length().valueOf();
            if (len<=0) return '(empty)';
            if (len>300000) return '[data '+len+'B 太大]';
            try { return o.bytes().readUtf8String(len); }
            catch(e){
                // protobuf 二进制, 转 hex 前 400 字节
                try {
                    var hx = o.bytes().readByteArray(Math.min(len,400));
                    return '[protobuf/binary '+len+'B, hex head]\n' + hexdump(hx, {length:Math.min(len,400)});
                } catch(e2){ return '[data '+len+'B unreadable]'; }
            }
        }
        if (cls.indexOf('Dictionary')>=0 || cls.indexOf('Array')>=0){
            try { return o.toString(); } catch(e){ return '[dict/array]'; }
        }
        return '[' + cls + ']';
    } catch(e){ return null; }
}

function hookSel(cls, selPattern, dataArgIdx){
    var C = ObjC.classes[cls];
    if (!C) return 0;
    var n = 0;
    C.$ownMethods.forEach(function(sel){
        if (sel.indexOf(selPattern) >= 0){
            try {
                Interceptor.attach(C[sel].implementation, {
                    onEnter: function(args){
                        try {
                            var url = urlOf(args[2]) || '(url?)';
                            if (/profile\/self|user\/profile|GetUserProfileSelf/i.test(url)){
                                var body = dataStr(args[dataArgIdx]);
                                hit('[★PROFILE/SELF★] ' + cls + ' ' + sel +
                                    '\nURL: ' + url + '\n--- BODY ---\n' + (body||'(none)') + '\n=========');
                            } else if (url.indexOf('http')===0){
                                log('[resp] ' + url.split('?')[0]);
                            }
                        } catch(e){ log('[onEnter-err]'+e); }
                    }
                });
                n++;
                log('[hook] ' + cls + ' -> ' + sel + ' (dataArg=' + dataArgIdx + ')');
            } catch(e){ log('[hook-err] '+cls+' '+sel+': '+e); }
        }
    });
    return n;
}

setTimeout(function(){
    // 找所有 serializer 类
    var targets = [];
    for (var cn in ObjC.classes){
        if (/ResponseSerializer/.test(cn)) targets.push(cn);
    }
    log('[serializer classes] ' + targets.join(', '));

    var total = 0;
    targets.forEach(function(cn){
        // jsonObj 版: response(a2) jsonObj(a3)
        total += hookSel(cn, 'responseObjectForResponse:jsonObj:', 3);
        // data 版: response(a2) data(a3)
        total += hookSel(cn, 'responseObjectForResponse:data:', 3);
    });
    log('[READY] 共hook ' + total + ' 个serializer方法, 现在点个人主页/下拉刷新, 盯 ★PROFILE/SELF★');
}, 500);
"""

def on_message(msg, data):
    if msg.get('type') == 'send':
        print(msg['payload'].get('m'), flush=True)
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
    run = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    end = time.time() + run
    while time.time() < end:
        time.sleep(1)
    print('[*] 结束(os._exit保护进程)', flush=True)
    import os; os._exit(0)

if __name__ == '__main__':
    main()
