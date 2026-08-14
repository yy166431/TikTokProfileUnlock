#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 写死1个类(不遍历ObjC.classes), 用该类$ownMethods返回的原始selector直接hook
# 单类$ownMethods已验证安全, 只挂1个方法
import sys, time, frida

DEVICE = "192.168.9.102:27042"
CLS = "TTHTTPJSONResponseSerializerBaseChromium"
SEL_KEY = "responseObjectForResponse:jsonObj:"   # 用它匹配$ownMethods里的真实sel

JS_TMPL = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
function hit(m){ send({t:'hit', m:m}); }

var CLS = "__CLS__";
var SEL_KEY = "__SEL_KEY__";

function urlOf(p){
    try {
        if (!p || p.isNull()) return null;
        var o = new ObjC.Object(p);
        try {
            var r = o.response();
            if (r && !r.isNull()){
                var u = new ObjC.Object(r).URL();
                if (u && !u.isNull()) return u.absoluteString().toString();
            }
        } catch(e){}
        try {
            var u2 = o.URL();
            if (u2 && !u2.isNull()){
                var s = u2.toString();
                return s.indexOf('http')===0 ? s : u2.absoluteString().toString();
            }
        } catch(e){}
    } catch(e){}
    return null;
}

setTimeout(function(){
    var C = ObjC.classes[CLS];       // 写死取, 不遍历
    if (!C){ log('[!] class 不存在: ' + CLS); return; }
    // 只对这一个类调 $ownMethods (已验证安全)
    var realSel = null;
    C.$ownMethods.forEach(function(s){
        if (s.indexOf(SEL_KEY) >= 0) realSel = s;
    });
    if (!realSel){ log('[!] 没找到含 ' + SEL_KEY + ' 的方法'); return; }
    log('[found] ' + CLS + ' -> ' + realSel);
    var m = C[realSel];
    if (!m){ log('[!] C[realSel] 取不到'); return; }
    try {
        Interceptor.attach(m.implementation, {
            onEnter: function(args){
                try {
                    // 0=self 1=_cmd 2=response 3=jsonObj 4=responseError 5=resultError
                    var url = urlOf(args[2]) || '(url?)';
                    if (/profile\/self|user\/profile/i.test(url)){
                        var body = '';
                        try { body = new ObjC.Object(args[3]).toString(); } catch(e){ body='(jsonObj读取失败)'; }
                        if (body.length > 6000) body = body.substring(0,6000) + '...[截断]';
                        hit('[PROFILE-SELF]\nURL: ' + url + '\n--- jsonObj ---\n' + body + '\n=====');
                    } else if (url.indexOf('http')===0){
                        log('[resp] ' + url.split('?')[0]);
                    }
                } catch(e){ log('[onEnter-err] '+e); }
            }
        });
        log('[OK] 已挂1个hook, 现在点个人主页/下拉刷新');
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
    js = JS_TMPL.replace('__CLS__', CLS).replace('__SEL_KEY__', SEL_KEY)
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
