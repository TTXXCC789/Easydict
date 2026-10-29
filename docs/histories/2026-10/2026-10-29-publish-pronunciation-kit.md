## 2026-10-29 | 任务：Publish pronunciation kit and user notebook

**Links:** [Completed plan](../../exec-plans/completed/2026-10/2026-10-29-publish-pronunciation-kit.md)

### 执行上下文

- **Agent Name:** `Unknown`
- **Model:** `GPT-6`
- **Environment:** `macOS 26.2 / Xcode Unknown (Command Line Tools only)`

### 用户请求

Upload a reusable repair kit to the user's GitHub and explain the SOP, changes, deployment, future improvements and usage experience.

### 变更

- Add a self-contained source kit and ZIP for Easydict 2.23.0.
- Add staged compile/sign/verify, recoverable backups, exact-process graceful stop, bounded Mach-O injection and restore.
- Add a Chinese user notebook, concrete change summary, troubleshooting SOP, development guide, manifest and validation record.
- Add entry links to both root READMEs; retain original author attribution and license.

### 设计意图

Keep the proven runtime source, distinguish this task's phonetic repair from older enhancements, and make fresh deployment reproducible. Do not copy system approvals or treat a visible switch/static signature as proof of working selection or sound.

### 验证

- Duplicate-app install and doctor: passed, including universal compilation and signature verification.
- Repeat install: one load command per architecture; restore: original executable hash recovered with prior version retained.
- Wrong version and nonempty header padding: refused safely.
- Python/shell syntax, Markdown links, scoped content scan, checksums and ZIP round-trip: passed.
- Read-only code/docs review: no blocking findings.
- Main application Xcode tests and Intel runtime verification were not run.

### 受影响文件

- `kits/pronunciation-repair/`
- `kits/releases/`
- `README.md`
- `README_ZH.md`
- This task's completed plan and history.

### 后续事项

- Expand compatibility only after per-version method checks and real runtime verification.
- Consider a normal source-build/signed release and fuller cancellation coverage as documented improvement work.
