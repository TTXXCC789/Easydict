# Easydict Pronunciation Kit · 2026.10.29

给已有 Easydict 增加和修复「划词 → 查词 → 听发音」的社区补丁套件。包含完整补丁源码、可回退安装器、排障 SOP，以及中文用户笔记。

**Easydict 原作者是 [@tisfeng](https://github.com/tisfeng)，上游项目是 [tisfeng/Easydict](https://github.com/tisfeng/Easydict)。本套件由社区 fork 整理，不是官方发行版，也不是重新开发了一款词典。** 保留原项目 [GPL-3.0 许可证](LICENSE)。

## 从哪里开始

| 你想做什么 | 阅读或执行 |
| --- | --- |
| 安装、配置、日常使用、分享使用心得 | [中文用户笔记](docs/USER-NOTEBOOK.zh-CN.md) |
| 了解本次到底改了什么 | [变更说明](docs/CHANGES.zh-CN.md) |
| 复现这次诊断与修复流程 | [排障 SOP](docs/SOP.zh-CN.md) |
| 改进、重新编译、维护和提交贡献 | [开发与改进指南](docs/DEVELOPMENT.zh-CN.md) |
| 核对验证范围及尚未验证的部分 | [验证记录](docs/VALIDATION.md) |

## 支持范围

- 安装器只接受 **Easydict 2.23.0**。应用使用内部 Objective-C 方法名，升级版本需重新检查兼容性。
- 实际使用验证环境：**macOS 26.2 / Apple Silicon（arm64）**。
- 补丁同时编译 **arm64 + x86_64**；没有实际 Intel Mac 的运行验证。
- 需要 Python 3 和 Apple Command Line Tools；无需完整 Xcode.app。缺少工具时先运行 `xcode-select --install`，完成系统安装后再继续。
- 这是源码构建套件，不包含完整 `.app`、个人词库、账号、API key、偏好设置或聊天日志。

## 快速部署

先从[上游 Releases](https://github.com/tisfeng/Easydict/releases)取得并安装官方 Easydict **2.23.0**。确认已放在 `/Applications/Easydict.app`。

打开 Terminal，进入解压后的本目录：

```bash
python3 scripts/kit.py doctor
python3 scripts/kit.py install
```

也可以双击 `Install.command`。安装器先在副本中编译、注入、签名和验证，成功后才备份并替换已安装应用。它不会下载代码、强杀全部 Easydict 进程、清除系统权限或修改翻译偏好。

**安装后必须刷新 Accessibility 的旧条目：**

1. 打开 **System Settings → Privacy & Security → Accessibility**。
2. 选中旧的 **Easydict** 行，点击减号移除；按系统要求自行完成 Touch ID。
3. 点击加号，明确选择 `/Applications/Easydict.app`，开启权限。
4. 从 Applications 启动或重启 Easydict。
5. 选中一个英文单词，让小图标出现；悬停或点击它打开词典，再分别点击 US / UK 音标旁的扬声器。

**仅关掉再打开旧开关可能无效。** 本次已实际遇到：开关显示开启，保存的审批却仍匹配旧的应用签名。完整说明见[用户笔记](docs/USER-NOTEBOOK.zh-CN.md#2-部署后最关键的一步刷新授权)。

本地签名验证成功不等于 Apple 公证通过，也不证明声音已经播出。如果 macOS 阻止启动，保留系统保护，使用备份恢复或改用正常签名的源码构建发行流程；套件不会关闭 Gatekeeper。

## 回退

安装器会打印本次备份的精确路径，默认位于：

```text
~/Library/Application Support/EasydictPronunciationKit/backups/<时间及唯一编号>/Easydict.app
```

使用打印的真实路径，保留引号：

```bash
python3 scripts/kit.py restore --backup "/实际备份目录/Easydict.app"
```

回退前还会备份当前版本。回退后可能需要按同样步骤重新添加 Accessibility 条目。不要把一个人的授权数据库或偏好设置复制给另一个人。

## What this kit changes

The 2026-10-29 fix recognizes a phonetic speaker click as a **new playback request**, even when a dictionary supplies an audio URL immediately. Earlier runtime logic rejected this URL as an outdated callback while idle. A scoped marker around `playWordPhonetic:designatedService:` fixes that distinction without accepting every forced-URL callback.

The kit also preserves the previously installed hover recovery, automatic pronunciation for longer text, configured TTS provider, and audio interruption behavior. The successful selection repair additionally required replacing a stale macOS Accessibility approval; that is an OS configuration step, not a code change.

Please report the macOS version, Easydict version, app where selection failed, which speaker failed, and whether the popup appears. Avoid sharing API keys or unredacted full logs.
