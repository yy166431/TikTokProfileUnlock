#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 终极方案: hook boringssl SSL_write/SSL_read 抓 HTTP 明文, 重点 profile
import sys, time, frida

DEVICE = "192.168.9.102:27042"

JS = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
function hit(m){ send({t:'hit', m:m}); }

// SSL_write(ssl, buf, num) -> 明文请求
// SSL_read(ssl, buf, num)  -> 明文响应
var pWrite = Module.findExportByName(null, 'SSL_write');
var pRead  = Module.findExportByName(null, 'SSL_read');

function bufToStr(buf, len){
    try {
        if (len <= 0) return '';
        if (len > 65536) len = 65536;
        return buf.readUtf8String(len);
    } catch(e){
        try { return buf.readCString(len); } catch(e2){ return null; }
    }
}

function looksHttp(s){
    if (!s) return false;
    return /^(GET|POST|PUT|DELETE|HEAD|OPTIONS|PATCH) /.test(s) ||
           s.indexOf('HTTP/1.') === 0;
}

if (pWrite){
    Interceptor.attach(pWrite, {
        onEnter: function(args){
            try {
                var buf = args[1];
                var num = args[2].toInt32();
                var s = bufToStr(buf, num);
                if (looksHttp(s)){
                    // 取请求行 + Host
                    var firstLine = s.split('\r\n')[0];
                    var host = '';
                    var hm = s.match(/[Hh]ost:\s*([^\r\n]+)/);
                    if (hm) host = hm[1];
                    var full = firstLine + '   [Host: ' + host + ']';
                    if (/profile|\/user\/|\/self\//i.test(s)){
                        // 命中! dump 整个请求头
                        var head = s.split('\r\n\r\n')[0];
                        hit('[PROFILE-REQ]\n' + head + '\n----------------');
                    } else {
                        // 全量打印 path (去掉超长query只留path+关键)
                        var pathOnly = firstLine.split('?')[0];
                        log('[W] ' + pathOnly + '   [' + host + ']');
                    }
                }
            } catch(e){}
        }
    });
    log('[+] SSL_write hooked @ ' + pWrite);
} else { log('[!] SSL_write not found'); }

if (pRead){
    Interceptor.attach(pRead, {
        onEnter: function(args){
            this.buf = args[1];
        },
        onLeave: function(ret){
            try {
                var n = ret.toInt32();
                if (n <= 0) return;
                var s = bufToStr(this.buf, n);
                if (s && /profile|"user"|unique_id|sec_uid|follower_count/i.test(s)){
                    hit('[PROFILE-RESP snippet]\n' + s.substring(0, 800) + '\n----------------');
                }
            } catch(e){}
        }
    });
    log('[+] SSL_read hooked @ ' + pRead);
} else { log('[!] SSL_read not found'); }

log('[READY] SSL层抓包启动! 去点个人主页/下拉刷新, 盯 [PROFILE-REQ]');
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
