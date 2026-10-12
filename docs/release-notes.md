本次更新整理退出入口，并采用分支开发、三端构建通过后合并的发布流程。

- 设置只保留设备名称和配对管理，移除「退出轻贴」。
- Mac 通过应用菜单（⌘Q）或菜单栏图标退出；Windows 右键托盘图标退出。
- Windows 托盘不可用时，关闭窗口直接退出，避免失去退出入口；正常关闭窗口仍驻留接收。
- PR 自动验证 Android、Windows、Mac 构建及测试，通过后合并，正式安装包由合并后的版本标签生成。

### 下载

- **Windows x64（推荐）**：`Lan-Clip-Windows-x64-Setup.exe`。升级前从托盘菜单「退出轻贴」，再运行新版安装包。ZIP 是完整解压后运行的便携备选。
- **Android**：通常选择 `Lan-Clip-Android-arm64-v8a.apk`；旧 32 位手机用 `armeabi-v7a`，模拟器用 `x86_64`。
- **Mac**：`Lan-Clip-Mac-universal.zip`，解压后放入「应用程序」。包含 Apple 芯片 / Intel 两种架构，需要 macOS 12+。

v0.1.0 正式 APK 可以覆盖安装，保留配对。更早的本地 Android 调试包仍需先卸载、安装正式包后重新配对。

所有产物由 GitHub Actions 构建，附 SHA-256。流水线验证协议与界面行为，Windows 额外执行安装、启动、升级和卸载测试。Windows 尚无发布者签名，Mac 使用本地签名、尚未 Apple 公证。

手机离开前台后可能被系统暂停，电脑显示离线不代表配对丢失；重新打开手机轻贴即可刷新。首次连接若系统询问本地网络访问，请允许；Windows 防火墙允许专用网络。跨真实 Android/Windows/Mac 的最终联调仍需用户设备复测。
