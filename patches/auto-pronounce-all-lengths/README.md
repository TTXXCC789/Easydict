# EasyDict Auto-Pronunciation for All Text Lengths
# EasyDict 全文本长度自动朗读与音频防重叠增强补丁

This patch fixes the issue where EasyDict only automatically pronounces single English words (`count <= 20` and `^[a-zA-Z]+$`), and does not automatically pronounce longer phrases, sentences, or paragraphs upon selection.

本方案解决了 EasyDict 官方版仅对单个英文短单词（长度 ≤ 20 且全字母）自动朗读，而划选长短语、长句子或段落时无法自动发音的问题。

---

## 1. 核心改进 (Core Improvements)

1. **解除发音文本长度与格式限制 (All Lengths Auto-Pronounce)**:
   - 单词、短语、长句子、甚至完整段落均可自动朗读。
   - 复用 EasyDict 原生的系统与网络 TTS 引擎（Google、Apple、有道等）。
2. **解决音频并发与重叠播放 Bug (Audio Overlap Prevention)**:
   - 发起新查询时自动截断上一段未播完的音频。
   - 引入会话代次标识（`playSessionId` / `Token`），自动丢弃网络慢速回调返回的过期音频数据。
   - 实现全局跨控制器音频互斥通知。

---

## 2. 源码修改记录 (Source Code Changes)

- `Easydict/objc/ViewController/Window/BaseQueryWindow/EZBaseQueryViewController.m`:
  - 将 `autoPlayEnglishWordAudio` 逻辑扩展为全文本长度 `autoPlayAudio`。
  - 在 `startQueryText:actionType:` 和 `queryCurrentModel` 时调用 `stopPlayingQueryText` 截断旧音频。
- `Easydict/objc/Service/QueryService/AudioPlayer/EZAudioPlayer.m`:
  - 增加动态 `playSessionId` 校验机制，过滤延迟的网络 TTS 回调。
  - 发送 `EZAudioPlayerDidStartPlayingNotification` 实现互斥。

---

## 3. 一键免 Xcode 注入补丁 (One-Click Binary Patch)

如果本地未安装完整的 Xcode.app（仅安装了 Command Line Tools），可以直接使用本目录下的二进制注入工具修补已安装的 `/Applications/Easydict.app`：

```bash
chmod +x install_patch.sh
./install_patch.sh
```

### 工具清单：
- `libeasydict_patch.m`: 基于 Objective-C Method Swizzling 的运行时独立动态库代码。
- `insert_dylib.py`: 跨架构 Mach-O `LC_LOAD_DYLIB` 注入脚本（支持 universal binary `arm64` + `x86_64`）。
- `install_patch.sh`: 包含自动备份、编译、注入、代码签名和权限重置的一键脚本。
