# 自动构建与签名

`.github/workflows/build.yml` 使用固定 Flutter 3.47.7 / JDK 21，在 GitHub 托管的 Linux、Windows、macOS 运行器上执行静态分析、测试、Release 构建。

Actions 页面选择 **Build Lan Clip → Run workflow**，三端产物在该次运行的 Artifacts 中。推送 `v*` 标签时，全部构建成功后会自动创建 GitHub Release，上传安装包与 SHA256SUMS.txt。更新发布前递增 `pubspec.yaml` 的版本号及 `+buildNumber`，并维护 `docs/release-notes.md`。

面向 `main` 的 PR 会自动执行三端完整构建与测试，Windows 还会运行安装、启动、升级和卸载验证。PR 不读取发布签名密钥，不上传分发包，也不创建 Release；Android 使用临时开发签名验证 Release 构建。只有三端检查全部通过后才合并，流程见 [AGENTS.md](../AGENTS.md)。

## Android

仓库需配置以下 Actions Secrets：

- `ANDROID_KEYSTORE_BASE64`：JKS 发布密钥库的 Base64。
- `ANDROID_KEYSTORE_PASSWORD`：密钥库密码。
- `ANDROID_KEY_ALIAS`：签名别名。
- `ANDROID_KEY_PASSWORD`：签名私钥密码。

标签发布和手动构建会在临时目录恢复密钥，构建结束后删除；缺少签名时直接失败。密钥不写入源码、日志或产物。当前仓库已配置固定发布密钥，本机备份在被忽略的 `.signing/` 内，应单独安全备份，不要提交到任何仓库。后续覆盖安装必须沿用同一密钥。

本地可设置 `ANDROID_KEYSTORE_PATH` 及三个密码/别名环境变量构建发布签名；不设置时使用 SDK 的调试密钥，仅供开发。`REQUIRE_RELEASE_SIGNING=true` 可禁止调试签名回退。

## macOS / Windows

Mac 构建检查 arm64 与 x86_64 两种架构，对完整应用进行本地签名验证后打包。Windows 分发完整 Flutter Release 目录，并从 Visual Studio 官方 Redistributable 目录复制 x64 Visual C++ 运行库，避免要求用户先安装开发环境。使用运行器附带的 Inno Setup 6 构建中文/英文安装向导，按当前用户安装；流水线会实际验证安装、快捷方式、原生接收进程启动、覆盖升级保留配对，以及卸载保留用户数据。Windows 便携 ZIP 同时保留。

目前未配置 Apple Developer ID、公证或 Windows 发布者代码签名证书。Android 的 APK 签名与这两种桌面发布者签名是不同机制。

## 图标

图形源和导出逻辑在 `tool/generate-icons.py`。安装 Pillow 后运行 `python3 tool/generate-icons.py`，统一生成 SVG、PNG、ICO、ICNS、菜单栏模板和 Android 自适应/单色图标。流水线直接使用已提交的图标资源，不在构建时依赖图像服务或下载字体。
