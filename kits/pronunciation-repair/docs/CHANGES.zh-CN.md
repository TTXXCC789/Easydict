# 本次改了什么

日期：2026-10-29。目标：选中英文后能进入查词，并通过音标旁的扬声器听到读音。

## 1. 本次新增的代码修复

位置：`src/libeasydict_patch.m`。

原调用链是：

```text
US/UK speaker → playWordPhonetic:designatedService:
             → playTextAudio:language:accent:audioURL:designatedService:forceURL:
             → 原生播放器
```

词典的扬声器按钮第一次点击就带着音频 URL。旧补丁把所有「带 URL 的调用」都当成异步回调；空闲状态下没有有效播放 token，或 `isPlaying` 为 false，于是直接丢弃。这就是点击没有声音的直接原因。

本次做了三处小改动：

1. 为真正的 `playWordPhonetic:designatedService:` 入口增加 scoped marker。
2. 把这个入口内的同步调用识别成新请求，建立播放会话，再交回原播放器。
3. 用 `@try/@finally` 恢复 marker，使之后到达的异步回调仍走原有取消检查。

没有把所有 `forceURL` 请求都放行，避免把延迟返回的旧请求错误地当作新点击。便于审查的本次增量见 [phonetic-speaker-fix.patch](phonetic-speaker-fix.patch)。该文件是对原有自定义补丁的增量；新用户部署使用完整 `src/`，不需要手工应用增量。

## 2. 本次修复的系统配置

重新签名改变了应用的代码签名标识。macOS 原先保存的 Accessibility 许可仍记录旧的 code requirement。

最初只刷新开关，UI 看起来已启用，但日志继续出现 `AXError.APIDisabled`。之后比对当前应用签名与系统保存的审批条件，证实它们不一致。最后通过系统设置删除旧行、重新添加当前 `/Applications/Easydict.app`，再重启应用，完成修复。

这是「授权对象更新」问题。Touch ID 必须由用户在自己的 Mac 上完成；无法随套件预先授权，也不需要复制或直接修改系统授权数据库。

## 3. 已有功能，本次继续保留

这些能力来自之前安装的定制补丁，不应被写成本次全部重新开发：

- 短词、词组、长句或段落的自动朗读入口。
- 首次悬停图标时的补充命中检测，避免图标出现在原有鼠标位置下却不触发。
- 同一次图标激活去重，避免重复查询与朗读重启。
- 开始新查询时中断旧声音，以及跨播放器的互斥处理。
- 自动朗读尊重用户选择的 TTS 服务；当时使用的是 Google。US/UK 词典按钮使用字典提供的发音资源。

这些既有保护没有在本次接受完整并发回归测试。请勿据此宣称所有网络竞态或所有文本长度都已穷尽验证。

## 4. 为分享套件新增的部署工具

这些工具在发布套件时整理，不是导致先前实机修复成功的额外运行补丁：

- `scripts/kit.py`：只接受已验证的 2.23.0，先处理副本，再备份与替换，提供静态诊断和回退。
- `scripts/inject_dylib.py`：检查 universal slices、load-command 边界、section 边界和空白空间；全部切片验证完成才写入；同一路径不重复注入。
- `Install.command`：启动源码构建安装。
- 文档：部署、授权刷新、验收、排障 SOP、使用心得和后续改进路线。

套件不会自动删除权限条目，不会直接写 TCC 数据库，不会关闭 macOS 安全保护，也不会把本机偏好上传到 GitHub。

## 5. 实际确认的结果

- 用户确认：小查词按钮重新出现，修改后的应用可用。
- 实机日志确认：在本聊天应用选中 `stale` 后触发 `auto_select_query`，打开查词窗口。
- 日志确认：自动朗读以及 US / UK 按钮均进入原生本地音频播放。
- US 和 UK 的 `sixth` 音频均可下载，并被系统识别为有效 MP3。
- 完整补丁的 arm64 / x86_64 编译通过，已安装 app 的签名验证通过。

更细的工具与发布验证范围见 [VALIDATION.md](VALIDATION.md)。
