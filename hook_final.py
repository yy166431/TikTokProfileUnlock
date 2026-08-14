#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 最终双hook (全写死类名, 零枚举):
#  响应侧: 14个binary serializer 的 responseObjectForResponse:data:...  -> URL+明文protobuf+解析对象
#  请求侧: TTHTTPRequestSerializerBaseChromium 的 URLRequestWith* -> 返回NSURLRequest的.URL+.HTTPBody(明文)
import sys, time, frida, json

DEVICE = "192.168.9.102:27042"

# 目标接口过滤(可多个)
URL_FILTER = "profile/self"

RESP_CLASSES = [
    "TTHTTPBinaryResponseSerializerBase", "AWEBinaryResponseSerializer",
    "AWEBinaryResponseSerializerForJSON", "AWEFeedPbResponseSerializer",
    "BDXBridgePbResponseSerializer", "HTSLivePBResponseSerializer",
    "TIMClientTTNetworkImpResponseSerializer", "TTIMStreakPBResponseSerializer",
    "TTKECProtobufResponseSerializer", "TTKFeedBasePbResponseSerializer",
    "TTKLandscapePostPbResponseSerializer", "TTKLanscapeFeedPbResponseSerializer",
    "TTKPaidContentPbBaseResponseSerializer", "TikTokKidsFeedPbResponseSerializer",
]
RESP_SEL = "responseObjectForResponse:data:responseError:resultError:"

REQ_CLASS = "TTHTTPRequestSerializerBaseChromium"
REQ_SELS = [
    "URLRequestWithRequestModel:commonParams:",
    "URLRequestWithURL:headerField:params:method:constructingBodyBlock:commonParams:",
    "URLRequestWithURL:params:method:constructingBodyBlock:commonParams:",
    "URLRequestWithURL:headerField:params:method:constructingBodyBlock:commonParams:bypassXWwwFormUrlencoded:",
]

JS_TMPL = r"""
'use strict';
function log(m){ send({t:'log', m:m}); }
function hit(m){ send({t:'hit', m:m}); }

var RESP_CLASSES = __RESP_CLASSES__;
var RESP_SEL = "__RESP_SEL__";
var REQ_CLASS = "__REQ_CLASS__";
var REQ_SELS = __REQ_SELS__;
var URL_FILTER = "__URL_FILTER__";

function urlOfResponse(p){
    try {
        if (!p || p.isNull()) return null;
        var o = new ObjC.Object(p);
        try { var u = o.URL(); if (u && !u.isNull()) return u.absoluteString().toString(); } catch(e){}
    } catch(e){}
    return null;
}

// NSData -> {len, text|hex}
function dataDump(p, maxLen){
    try {
        if (!p || p.isNull()) return '(null)';
        var o = new ObjC.Object(p);
        var cls = o.$className || '';
        if (cls.indexOf('Data') < 0) {
            // 可能是字典/model, 直接description
            try { return '['+cls+'] ' + o.description().toString().substring(0,maxLen); } catch(e){ return '['+cls+']'; }
        }
        var len = o.length().valueOf();
        if (len <= 0) return '(empty data)';
        var take = Math.min(len, maxLen);
        var bytes = o.bytes();
        // 先试utf8
        var txt = null;
        try { txt = bytes.readUtf8String(take); } catch(e){}
        var out = 'len=' + len;
        if (txt && /[\x20-\x7e]/.test(txt) && txt.length > 0){
            out += '\n[utf8?]\n' + txt;
        }
        // 总是附hex head(protobuf二进制)
        try {
            var hx = bytes.readByteArray(Math.min(take, 512));
            out += '\n[hex head]\n' + hexdump(hx, {length: Math.min(take,512), header:false});
        } catch(e){}
        return out;
    } catch(e){ return '(dataDump-err '+e+')'; }
}

function objDump(p, maxLen){
    try {
        if (!p || p.isNull()) return '(null)';
        var o = new ObjC.Object(p);
        var s = '';
        try { s = o.description().toString(); } catch(e){ s = o.toString(); }
        if (s.length > maxLen) s = s.substring(0, maxLen) + '...[截断]';
        return '['+(o.$className||'?')+']\n' + s;
    } catch(e){ return '(objDump-err '+e+')'; }
}

// ---- 响应侧 ----
function hookRespClass(cn){
    var C = ObjC.classes[cn];
    if (!C) return;
    var real = null;
    C.$ownMethods.forEach(function(s){ if (s.indexOf(RESP_SEL) >= 0) real = s; });
    if (!real) return;
    try {
        Interceptor.attach(C[real].implementation, {
            onEnter: function(args){
                this.url = urlOfResponse(args[2]) || '';
                this.data = args[3];
                this.hit = (this.url.indexOf(URL_FILTER) >= 0);
                if (this.hit){
                    hit('[★RESP REQUEST★] serializer=' + cn + '\nURL: ' + this.url +
                        '\n--- 明文protobuf(解压后) ---\n' + dataDump(this.data, 4000));
                } else if (this.url.indexOf('http')===0){
                    log('[resp] '+cn+' ' + this.url.split('?')[0]);
                }
            },
            onLeave: function(ret){
                if (!this.hit) return;
                hit('[★RESP PARSED OBJECT★] URL: ' + this.url +
                    '\n--- 解析后对象 ---\n' + objDump(ret, 6000) + '\n==========');
            }
        });
        log('[hook-resp] ' + cn);
    } catch(e){ log('[hook-resp-err] '+cn+' '+e); }
}

// ---- 请求侧 ----
function hookReqSel(C, selKey){
    var real = null;
    C.$ownMethods.forEach(function(s){ if (s.indexOf(selKey) >= 0 && s.length === selKey.length + 2) real = s; });
    if (!real){ C.$ownMethods.forEach(function(s){ if (s.indexOf(selKey) >= 0 && !real) real = s; }); }
    if (!real){ log('[req-skip] '+selKey); return; }
    try {
        Interceptor.attach(C[real].implementation, {
            onLeave: function(ret){
                try {
                    if (!ret || ret.isNull()) return;
                    var req = new ObjC.Object(ret);
                    var url = '';
                    try { var u = req.URL(); if (u && !u.isNull()) url = u.absoluteString().toString(); } catch(e){}
                    if (url.indexOf(URL_FILTER) < 0) return;
                    var method = ''; try { method = req.HTTPMethod().toString(); } catch(e){}
                    var body = '(no body)';
                    try { var b = req.HTTPBody(); if (b && !b.isNull()) body = dataDump(b, 4000); } catch(e){}
                    hit('[★REQ BODY★] via ' + real + '\n' + method + ' ' + url +
                        '\n--- 明文请求体 ---\n' + body + '\n==========');
                } catch(e){ log('[req-onLeave-err] '+e); }
            }
        });
        log('[hook-req] ' + real);
    } catch(e){ log('[hook-req-err] '+selKey+' '+e); }
}

setTimeout(function(){
    RESP_CLASSES.forEach(hookRespClass);
    var RC = ObjC.classes[REQ_CLASS];
    if (RC){ REQ_SELS.forEach(function(sk){ hookReqSel(RC, sk); }); }
    else log('[!] '+REQ_CLASS+' 不存在');
    log('[READY] 双hook挂载完成. 现在: 点个人主页/下拉刷新, 盯 ★REQ BODY★ / ★RESP REQUEST★ / ★RESP PARSED OBJECT★');
}, 600);
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
    js = (JS_TMPL
          .replace('__RESP_CLASSES__', json.dumps(RESP_CLASSES))
          .replace('__RESP_SEL__', RESP_SEL)
          .replace('__REQ_CLASS__', REQ_CLASS)
          .replace('__REQ_SELS__', json.dumps(REQ_SELS))
          .replace('__URL_FILTER__', URL_FILTER))
    scr = sess.create_script(js)
    scr.on('message', on_message)
    scr.load()
    run = int(sys.argv[1]) if len(sys.argv) > 1 else 240
    end = time.time() + run
    while time.time() < end:
        time.sleep(1)
    print('[*] 结束(os._exit保护)', flush=True)
    import os; os._exit(0)

if __name__ == '__main__':
    main()
