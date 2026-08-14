#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# hook GPBMessage(protobuf基类)的 parseFromData:/initWithData:, onEnter判断self类名
# 只在 self==GetUserProfileSelfResponse 时抓, 精准过滤, 不遍历
import sys, time, frida

DEVICE = "192.168.9.102:27042"
TARGET = "GetUserProfileSelfResponse"

JS_TMPL = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
function hit(m){ send({t:'hit', m:m}); }

var TARGET = "__TARGET__";

function clsNameOf(p){
    try {
        if (!p || p.isNull()) return '';
        var o = new ObjC.Object(p);
        return o.$className || o.toString();
    } catch(e){ return ''; }
}

function dumpRet(ret, tag, dlen){
    try {
        if (!ret || ret.isNull()){ log('[pb] '+tag+' ret null dlen='+dlen); return; }
        var o = new ObjC.Object(ret);
        if ((o.$className||'').indexOf(TARGET) < 0) return; // 只要目标
        var body = '';
        try { body = o.description().toString(); }
        catch(e){ try { body = o.toString(); } catch(e2){ body='(desc失败)'; } }
        if (body.length > 9000) body = body.substring(0,9000) + '...[截断]';
        hit('[★PROFILE-SELF PB★] via '+tag+' dlen='+dlen+'\n--- fields ---\n'+body+'\n=====');
    } catch(e){ log('[dump-err]'+e); }
}

function hookClassMethod(C, selKey){
    var real = null;
    C.$ownMethods.forEach(function(s){ if (s.indexOf(selKey) >= 0) real = s; });
    if (!real){ log('[skip] '+C.$className+' 无 '+selKey); return; }
    log('[hook] ' + C.$className + ' ' + real);
    try {
        Interceptor.attach(C[real].implementation, {
            onEnter: function(args){
                this.match = false; this.dlen = 0; this.sk = selKey;
                try {
                    // 类方法: args[0]=接收类; 实例方法: args[0]=实例. 两种都取类名判断
                    var nm = clsNameOf(args[0]);
                    if (nm.indexOf(TARGET) >= 0) this.match = true;
                    var d = new ObjC.Object(args[2]);
                    if (d && d.$className && d.$className.indexOf('Data')>=0) this.dlen = d.length().valueOf();
                } catch(e){}
            },
            onLeave: function(ret){
                gCount++;
                if (this.match){ dumpRet(ret, this.sk, this.dlen); return; }
                // 非目标: 记录见过的类名(去重, 最多报20个不同的)
                try {
                    var nm = clsNameOf(ret);
                    if (nm && seen.indexOf(nm) < 0 && seen.length < 40){
                        seen.push(nm);
                        log('[pb-cls] ' + nm);
                    }
                } catch(e){}
            }
        });
    } catch(e){ log('[attach-err] '+C.$className+' '+e); }
}

setTimeout(function(){
    var G = ObjC.classes.GPBMessage;
    if (!G){ log('[!] GPBMessage 不存在'); return; }
    // 类方法: +parseFromData:error: (self=class) -> ret=新实例
    hookClassMethod(G, 'parseFromData:error:');
    // 实例方法: -initWithData:error: (self=实例, 已是目标类) -> ret=self
    hookClassMethod(G, 'initWithData:error:');
    log('[OK] hook GPBMessage上了(过滤'+TARGET+'), 点个人主页/下拉刷新');
}, 500);
"""

def on_message(msg, data):
    if msg.get('type') == 'send':
        print(msg['payload'].get('m'), flush=True)
    elif msg.get('type') == 'error':
        print('[JS-ERR]', msg.get('description'), flush=True)

def on_detached(reason):
    print('[!!! DETACHED]', reason, flush=True)

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
    sess.on('detached', on_detached)
    scr = sess.create_script(JS_TMPL.replace('__TARGET__', TARGET))
    scr.on('message', on_message)
    scr.load()
    run = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    end = time.time() + run
    while time.time() < end:
        time.sleep(1)
    print('[*] 结束(os._exit保护)', flush=True)
    import os; os._exit(0)

if __name__ == '__main__':
    main()
