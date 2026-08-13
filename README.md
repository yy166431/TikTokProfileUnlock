# TikTok Network Dump

TikTok/抖音个人中心网络请求抓包插件

## 功能

- 拦截进入个人中心时的所有网络请求
- 保存完整的请求URL、请求头、请求体
- 保存完整的响应头、响应体（包括格式化的JSON）
- 自动保存到 `/var/mobile/Documents/TikTokDump/`

## 使用方法

### 方法1: TrollStore安装（推荐）

1. 下载Release中的 `.deb` 文件
2. 用TrollStore打开安装
3. 重启抖音/TikTok
4. 进入个人中心页面
5. 用Filza查看 `/var/mobile/Documents/TikTokDump/` 目录

### 方法2: 手动注入dylib

1. 下载Release中的 `.dylib` 文件
2. 用注入工具注入到抖音/TikTok
3. 重启应用

## 文件说明

dump出来的文件：
- `request_时间戳.txt` - 请求信息（URL、请求头、请求体）
- `response_时间戳.txt` - 响应信息（状态码、响应头、响应体）
- `response_时间戳.json` - 格式化的JSON响应体

## 支持的Bundle ID

- `com.zhiliaoapp.musically` - TikTok国际版
- `com.ss.iphone.ugc.Aweme` - 抖音国内版

## 编译

需要Theos环境：

```bash
make clean
make package
```

或者直接用GitHub Actions自动编译

## 注意事项

- 需要越狱或TrollStore环境
- 保存的文件在 `/var/mobile/Documents/TikTokDump/`
- 可以用Filza或iFunBox查看

## 作者

海鸥

## License

MIT
