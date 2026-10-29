# 开发与改进指南

## 代码地图

| 文件 | 职责 |
| --- | --- |
| `src/libeasydict_patch.m` | Objective-C method swizzling；保留旧的 hover、自动朗读、互斥逻辑，增加本次 phonetic 新请求识别 |
| `scripts/inject_dylib.py` | 对 Mach-O 添加 patch library 的 load command；严格验证可写 header 空间 |
| `scripts/kit.py` | 版本检查、源码编译、签名、备份、替换、静态诊断与恢复 |
| `docs/phonetic-speaker-fix.patch` | 本次相对于已有补丁的最小增量 |

## 修改与本地验证

建议从自己的 fork 分支开始。修改后先编译独立库，不需要替换正在工作的 app：

```bash
mkdir -p build
xcrun clang -dynamiclib -arch arm64 -arch x86_64 -fobjc-arc \
  -framework Foundation -framework AppKit -framework AVFoundation \
  -install_name @rpath/libeasydict_patch.dylib \
  src/libeasydict_patch.m -o build/libeasydict_patch.dylib
lipo -info build/libeasydict_patch.dylib
python3 -m py_compile scripts/kit.py scripts/inject_dylib.py
bash -n Install.command
```

检查差异，再让另一个审查者核对真实调用链、取消行为、method type 与异常清理。编译只能说明能生成库，不能说明私有方法在未来 app 版本中仍然相同。

要升级兼容版本时，先从上游对应版本核对以下方法、参数和行为，再在独立副本中验收；仅修改 `VERSION` 常量是不够的：

- `EZAudioPlayer` 的 `playWordPhonetic:designatedService:` 与六参数 `playTextAudio...forceURL:`。
- 查询控制器的初始化、查询、停止播放与关闭结果逻辑。
- 选词图标窗口与窗口管理器的激活及生命周期。
- 现有补丁读取的 KVC 属性。

## 建议的改进顺序

1. **先回归真实使用路径。** 把“选区没读到”“点击被取消”“音频资源错误”“设备没声音”分开观察，不用一个通用“播放失败”提示掩盖。
2. **让修复进入正常源码构建。** 将 phonetic 入口与会话区分移到相应播放器实现，逐步减少 swizzling。这样更利于维护与提交上游。
3. **补足取消与并发覆盖。** 现有补丁已有 token/互斥机制，但不是本次证明其完整正确性。改进时要验证：连续选词、停止后旧请求返回、跨播放器切换、完成回调晚到、US/UK 快速切换。
4. **为正式分发准备稳定签名流程。** 当前 kit 本地编译后 ad-hoc 签名；普通用户每次换签名可能要刷新授权。正式发行应采用项目正常构建、签名与 Apple 公证流程，不能用关闭 Gatekeeper 代替。
5. **跨环境实测。** 增加 Intel、不同 macOS、浏览器/阅读器/聊天 app 的验收记录。确认后再扩大支持列表。

以上是后续路线，尚未宣称已实现或已覆盖所有测试场景。

## 发布一个新 kit

- 更新版本标识、支持 app 版本和变更说明。
- 审查源码及脚本，验证副本上的安装、重复安装、失败不改原件与回退。
- 对真实新构建完成签名和 Accessibility 刷新后再做选词与发音试听。
- 更新 `VALIDATION.md`，把未测的环境写清楚。
- 重新生成 `SHA256SUMS` 和 ZIP。不要把 `build/`、`__pycache__/`、本机 `.app` 或偏好提交进去。

仓库中的 kit 自包含完整源码。修改 Easydict 主工程时还应遵守仓库根 `AGENTS.md` 的构建、测试和审查规则；本次 kit 的编译结果不能代替主工程完整 Xcode 验证。
