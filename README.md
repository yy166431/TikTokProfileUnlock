# TikTok Network Capture

TikTok/抖音个人中心网络请求抓包插件 - 带悬浮窗和HTTP服务器

## ✨ 功能

- 🎯 拦截进入个人中心时的所有API请求
- 📡 捕获完整的请求URL（含所有query参数）
- 📋 捕获所有请求头（包括设备指纹、SDK版本等）
- ✅ 捕获完整的响应JSON（自动格式化）
- 🔴 悬浮窗实时显示抓包数量
- 🌐 内置HTTP服务器，Safari浏览器实时查看

## 🎯 抓包示例

### 完整URL（含所有参数）
```
https://api32-core-alisg.tiktokv.com/tiktok/user/profile/self/v1?
  residence=BR&
  device_id=7669723600929195540&
  os_version=18.0&
  iid=7669725810324391701&
  app_name=musical_ly&
  locale=en&
  ac=WIFI&
  sys_region=BR&
  version_code=44.8.0&
  ...
```

### 请求头（设备指纹/SDK）
- `user-agent`: TikTok 44.8.0 rv:448030 (iPhone; iOS 18.0)
- `oec-cs-sdk-version`: v10.02.04_V55
- `x-vc-bdturing-sdk-version`: 2.4.2
- `passport-sdk-version`: 5.12.1
- `oec-vc-sdk-version`: 3.2.2:i18n
- `x-tt-pba-encode`: 4020
- `rpc-persist-pns-region`: JPl1861060
- `x-tt-store-region`: br
- 还有更多...

### 响应JSON
完整的用户Profile数据，自动格式化

## 📱 使用方法

### 方法1: TrollStore安装（推荐）

1. 下载Release中的 `.deb` 文件
2. 用TrollStore打开安装
3. 重启抖音/TikTok
4. **红色悬浮窗**会自动出现
5. 进入个人中心页面
6. 用Safari访问 `http://设备IP:9999` 查看抓包数据

### 方法2: 手动注入dylib

1. 下载Release中的 `.dylib` 文件
2. 用注入工具注入到抖音/TikTok
3. 重启应用

## 🌐 查看抓包数据

### Safari浏览器查看
1. 确保手机和电脑在同一WiFi
2. 手机打开TikTok，出现红色悬浮窗
3. 进入个人中心（触发抓包）
4. 电脑浏览器访问: `http://手机IP:9999`
5. 实时查看所有抓包数据（自动刷新页面即可）

### 悬浮窗功能
- 显示抓包数量
- 可以拖动位置
- 红色=正在运行

## 📝 抓包内容说明

每条抓包记录包含：
- ⏰ **请求时间** - 精确到秒
- 🌐 **完整URL** - 包含所有query参数
- 📋 **所有请求头** - 设备指纹、SDK版本、签名等
- ✅ **完整响应** - JSON格式，自动美化


## 🎯 支持的Bundle ID

- `com.zhiliaoapp.musically` - TikTok国际版
- `com.ss.iphone.ugc.Aweme` - 抖音国内版

## 🔧 编译

需要Theos环境：

```bash
make clean
make package
```

或者直接用**GitHub Actions自动编译**，每次push自动构建

## 💡 技术细节

- Hook `NSURLSession` 拦截HTTP请求
- 使用 `CFSocket` 实现HTTP服务器（端口9999）
- 悬浮窗使用 `UIButton + UIPanGestureRecognizer` 可拖动
- 自动保存最近100条抓包记录（超过自动删除旧的）
- 响应JSON自动格式化（`NSJSONSerialization`）

## ⚠️ 注意事项

- 需要越狱或TrollStore环境
- HTTP服务器端口: **9999**
- 悬浮窗可能被其他UI遮挡，可以拖动
- 只抓取包含 `profile` 或 `user` 的API请求
- 电脑和手机必须在同一WiFi才能访问

## 🐛 故障排除

### 看不到悬浮窗
- 重启TikTok应用
- 检查插件是否正确安装

### 无法访问HTTP服务器
- 确保手机和电脑在同一WiFi
- 检查手机IP地址是否正确
- 尝试关闭防火墙

### 没有抓到数据
- 确保已进入个人中心页面
- 检查悬浮窗计数是否增加
- 查看Console日志（XCode）

## 📄 License

MIT

## 👨‍💻 作者

海鸥

---

**提示**: 仅用于学习研究，请勿用于非法用途！
