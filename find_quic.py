#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 分析 libquic.dylib + boringssl 导出, 找 QUIC 明文出口
import sys, time, frida

DEVICE = "192.168.9.102:27042"

JS = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
setTimeout(function(){
    try {
        // libquic 的导出符号里找 send/write/stream/header 相关
        var quic = Process.findModuleByName('libquic.dylib');
        if (quic){
            log('=== libquic.dylib exports (send/write/stream/header/data) ===');
            var exps = quic.enumerateExports();
            log('total exports = ' + exps.length);
            var cnt=0;
            exps.forEach(function(e){
                var n = e.name.toLowerCase();
                if ((n.indexOf('send')>=0 || n.indexOf('write')>=0 || n.indexOf('stream')>=0 ||
                     n.indexOf('header')>=0 || n.indexOf('request')>=0 || n.indexOf('encode')>=0) && cnt<60){
                    log('  ' + e.name);
                    cnt++;
                }
            });
        } else {
            log('libquic.dylib not found as module');
        }

        // TikTok 自带 boringssl(非系统) 里的 SSL_write 地址范围
        log('=== boringssl module ===');
        var bs = Process.findModuleByName('boringssl');
        if (bs) log('boringssl base=' + bs.base + ' size=' + bs.size);
        var w = Module.findExportByName(null, 'SSL_write');
        log('SSL_write=' + w + ' (在boringssl内? ' + (bs && w.compare(bs.base)>=0 && w.compare(bs.base.add(bs.size))<0) + ')');

        // 找 cronet / QUIC 的 http header 序列化: SpdyHeaderBlock / QuicHeaderList
        log('=== 找 http3/spdy/quic 符号(用DebugSymbol) ===');
        ['SSL_do_handshake','SSL_provide_quic_data','SSL_set_quic_method','BIO_write'].forEach(function(fn){
            var p = Module.findExportByName(null, fn);
            log('  ' + fn + ' => ' + (p ? p : 'null'));
        });
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
time.sleep(5)
print('[*] done', flush=True)
