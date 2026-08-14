#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 最小验证: 只挂 1 个类 TTHTTPBinaryResponseSerializerBase
# 非目标流量啥都不做(不log), 只在命中 profile/self 时输出
import sys, time, frida

DEVICE = "192.168.9.102:27042"
CLS = "TTHTTPBinaryResponseSerializerBase"
SEL_KEY = "responseObjectForResponse:data:"
URL_FILTER = "profile/self"

JS_TMPL = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
function hit(m){ send({t:'hit', m:m}); }
var CLS = "__CLS__", SEL_KEY = "__SEL_KEY__", URL_FILTER = "__URL_FILTER__";

function urlOf(p){
    try { if(!p||p.isNull())return ''; var o=new ObjC.Object(p);
        var u=o.URL(); if(u&&!u.isNull()) return u.absoluteString().toString(); } catch(e){}
    return '';
}
function dataDump(p, maxLen){
    try {
        if(!p||p.isNull())return '(null)';
        var o=new ObjC.Object(p); var cls=o.$className||'';
        if(cls.indexOf('Data')<0) return '['+cls+']';
        var len=o.length().valueOf(); if(len<=0)return '(empty)';
        var take=Math.min(len,maxLen); var b=o.bytes();
        var out='len='+len; var txt=null;
        try{ txt=b.readUtf8String(take); }catch(e){}
        if(txt) out+='\n[utf8?]\n'+txt;
        try{ out+='\n[hex]\n'+hexdump(b.readByteArray(Math.min(take,512)),{length:Math.min(take,512),header:false}); }catch(e){}
        return out;
    } catch(e){ return '(err '+e+')'; }
}

setTimeout(function(){
    var C = ObjC.classes[CLS];
    if(!C){ log('[!] 不存在 '+CLS); return; }
    var real=null;
    C.$ownMethods.forEach(function(s){ if(s.indexOf(SEL_KEY)>=0) real=s; });
    if(!real){ log('[!] 无 '+SEL_KEY); return; }
    log('[found] '+CLS+' -> '+real);
    try {
        Interceptor.attach(C[real].implementation, {
            onEnter: function(args){
                this.hit=false;
                try {
                    var url=urlOf(args[2]);
                    if(url.indexOf(URL_FILTER)>=0){
                        this.hit=true; this.url=url;
                        hit('[★RESP★] '+CLS+'\nURL: '+url+'\n--- 明文 ---\n'+dataDump(args[3],4000));
                    }
                } catch(e){}
            }
        });
        log('[OK] 挂1个hook(最小), 点个人主页/下拉刷新');
    } catch(e){ log('[hook-err] '+e); }
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
    js = (JS_TMPL.replace('__CLS__',CLS).replace('__SEL_KEY__',SEL_KEY).replace('__URL_FILTER__',URL_FILTER))
    scr = sess.create_script(js)
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
