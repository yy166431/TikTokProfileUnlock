#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 精准只钩 1 个方法: TTNetworkManagerChromium handleUpperLayerCallback:dispatchQueue:requestUrl:
# onEnter 只读明确的字符串参数, 最小化崩溃风险
import sys, time, frida

DEVICE = "192.168.9.102:27042"

JS = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
function hit(m){ send({t:'hit', m:m}); }

setTimeout(function(){
    var C = ObjC.classes.TTNetworkManagerChromium;
    if (!C){ log('[!] TTNetworkManagerChromium missing'); return; }

    // 目标方法: handleUpperLayerCallback:dispatchQueue:requestUrl:
    var sel = null;
    C.$ownMethods.forEach(function(s){
        if (s.indexOf('handleUpperLayerCallback:') >= 0 && s.indexOf('requestUrl:') >= 0){
            sel = s;
        }
    });
    if (!sel){ log('[!] handleUpperLayerCallback method not found'); return; }
    log('[target] ' + sel);

    // 数参数个数, requestUrl 是第3个参数 => args[4] (args[0]=self,args[1]=sel,args[2]=cb,args[3]=queue,args[4]=url)
    try {
        Interceptor.attach(C[sel].implementation, {
            onEnter: function(args){
                try {
                    var p = args[4];
                    if (p && !p.isNull()){
                        var o = new ObjC.Object(p);
                        var cls = o.$className || '';
                        if (cls.indexOf('String') >= 0 || cls.indexOf('URL') >= 0){
                            var u = o.toString();
                            if (u && u.indexOf('http') === 0){
                                if (/profile|\/user\/|\/self\/|aweme\/v1\/user/i.test(u)){
                                    hit('[PROFILE] ' + u);
                                } else {
                                    log('[url] ' + u.split('?')[0]);
                                }
                            }
                        }
                    }
                } catch(e){}
            }
        });
        log('[OK] hooked 1 method, 现在刷抖音+点个人主页');
    } catch(e){ log('[hook-err] ' + e); }
}, 400);
"""

def on_message(msg, data):
    if msg.get('type') == 'send':
        print(msg['payload'].get('m'), flush=True)
    elif msg.get('type') == 'error':
        print('[JS-ERR]', msg.get('description'), flush=True)

def on_detached(reason):
    print('[!!!] DETACHED:', reason, flush=True)

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
    scr = sess.create_script(JS)
    scr.on('message', on_message)
    scr.load()
    run = int(sys.argv[1]) if len(sys.argv) > 1 else 180
    end = time.time() + run
    while time.time() < end:
        time.sleep(1)
    print('[*] 结束', flush=True)

if __name__ == '__main__':
    main()
