# Publish pronunciation kit and user notebook

- 状态：completed
- 创建日期：2026-10-29
- 负责人：Unknown
- 关联 Issue/PR：none

## 执行上下文

- **Agent Name:** `Unknown`
- **Model:** `GPT-6`
- **Environment:** `macOS 26.2 / Xcode Unknown (Command Line Tools only)`

## 背景

The user confirmed the repaired app works and requested a reusable GitHub kit, SOP, change summary, deployment/improvement notes and usage experience.

## 目标与范围

- 目标结果：A source kit and downloadable ZIP, with a Chinese user notebook discoverable from both repository READMEs.
- 允许修改路径：`kits/`, the two root READMEs, and this task's plan/history.
- 同任务 history：`docs/histories/2026-10/2026-10-29-publish-pronunciation-kit.md`
- 用户限制：No user configuration, logs, authorization database or application bundle in the package.
- 非目标：Changing the currently working app or incorporating unrelated local changes.
- 验收标准：Compile and review deployment tools; validate install/reinstall/restore on disposable copies; verify package and publication.

## 工作计划

1. Capture the successful runtime source and separate new fixes from retained features.
2. Prepare staged installation, verified backups, bounded injection and rollback.
3. Write the user notebook, SOP, change log, improvement guide and validation record.
4. Review, package and publish in the user's existing fork.

## 风险与决策

- Pin installation to Easydict 2.23.0; Intel runtime and other versions remain unverified.
- Accessibility approvals may remain bound to old signatures. Document remove/re-add and user-completed authentication.
- Publish source and ZIP without personal runtime data; retain upstream attribution and GPL license.
- Standalone kit is outside the Xcode build graph. Compile its universal library directly; do not claim full application tests.

## 进度

- [x] Prepare runtime source, deployment tools and documentation.
- [x] Validate duplicate installation, repeated installation, rollback and refusal paths.
- [x] Review scripts/docs and package the kit.
- [x] Prepare one scoped GitHub commit; confirm the resulting default-branch contents after publication.

## 验证

- Universal compilation, codesign, doctor, repeat installation and rollback: passed on disposable app copies.
- Unsupported-version refusal, nonempty header refusal and idempotent injection: passed.
- Python compilation, shell syntax, relative Markdown links, scoped content scan, file hashes and ZIP round-trip: passed.
- Read-only code review: no blocking findings for the supported deployment path.
- Full application Xcode tests and Intel runtime behavior: not run.

## 完成条件

- All kit checks completed and the uploaded kit, notebook and downloadable ZIP are present on the user's fork.
