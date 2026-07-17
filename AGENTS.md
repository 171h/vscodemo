# AGENTS.md — AI 开发指南

本文件是 AI 编码代理（Claude Code、Codex 等）在本仓库工作的规则手册。
人类贡献者同样适用。

## 协作语言

- AI 代理在本仓库工作时，向用户呈现的思考过程、执行计划、取舍说明、
  阶段性进展、结果总结与复盘必须使用中文。
- 代码标识符、命令、日志、错误信息、第三方 API 名称、提交 type/scope
  等固定格式内容可以保留原文；必要时用中文解释其含义和影响。

## 项目概览

本仓库将 [microsoft/vscode](https://github.com/microsoft/vscode) 魔改为建筑计算
软件基础平台（MagicStudio），使用 VSCodium 构建链。核心是五层叠加模型：

| 层 | 位置 | 职责 |
| --- | --- | --- |
| L4 | `product/` | 品牌与 product.json 覆盖 |
| L3 | `extensions/` | 自研内置扩展（功能主战场） |
| L2 | `patches/` + `removals.json` | 手写核心补丁 + 大规模裁剪清单 |
| L1 | `vscodium/`（submodule） | VSCodium 构建链，锁定 release |
| L0 | `vscode/`（gitignore） | 上游源码工作副本，**只读、不入库** |

完整计划见文档站（`pnpm docs:dev`），入口 `docs/plan/index.md`。

## 铁律

1. **绝不把 `vscode/` 的改动直接入库**。任何对上游源码的修改必须固化为
   `patches/*.patch`、`extensions/` 扩展或 `removals.json` 清单项。
2. **版本只认 `upstream.lock.json`**。升级走 `bash scripts/upgrade.sh <tag>`，
   不要手工改 vscode 检出或 vscodium 子模块的版本。
3. **`patches/generated/` 禁止手工编辑**——它是 `removals.json` 的自动展开
   结果，由 `bash scripts/gen-removals-patch.sh` 重新生成。
4. **实现新功能先走扩展**（代码分离阶梯：扩展 → product.json → 注入点补丁 →
   行为修改补丁）；**移除既有功能走 `removals.json`**，不写手工补丁。
5. **登记义务**：新增/修改手写补丁 → `docs/implementation/` 补丁登记表；
   剥离 contribution → 先做依赖闭包分析并登记；每次升级 → `docs/changelog/`。
6. 改动 `docs/` 后必须 `pnpm docs:build` 验证通过（含死链检查）。

## GitHub Actions 稳定性守则

本仓库的本地开发模式与发行 CI 模式不是同一条补丁应用路径：本地
`scripts/prepare.sh` 直接把本仓库补丁叠到干净 `vscode/`；GitHub Actions
中的 `scripts/build.sh` 会先走 VSCodium 构建链，先应用 VSCodium 官方补丁，
再应用 `patches/user/` 中的本仓库补丁。因此，凡是修改 `patches/`、
`removals.json`、构建脚本或 code-separation 相关机制，必须提前考虑
**与 VSCodium 既有改动重复或上下文冲突**的问题。

- 新增/修改手写补丁前，先检查同一上游文件是否已被 `vscodium/patches/*.patch`
  或本仓库 `patches/vscodium/` 触碰；补丁 hunk 的上下文不要锚在 VSCodium
  已经会改写的相邻行上。必要时提供 `patches/vscodium/` 后置基线版本。
- 补丁必须同时兼容两种顺序：干净 vscode + 本仓库补丁（开发模式），以及
  VSCodium 官方补丁 + 本仓库补丁（发行 CI）。不要只用 `prepare.sh` 成功
  来判断 CI 一定成功。
- 清理菜单、contribution 或 import 时，不要把“当前 hunk 删除了某个使用点”
  误判为“全文件不再需要该符号”。删除 import 前必须反查幸存引用；典型风险是
  某个菜单项被删了，但同文件 StatusBar、QuickAccess、服务注册仍在用同一符号。
- 修改 `removals.json` 前必须做依赖闭包分析：`MainThread*`/`ExtHost*` 接线、
  构造器注入的 service contribution、其他 contribution 的静态 import 都可能把
  被剥离模块重新拉起或导致运行时/编译期缺依赖。
- Windows Actions 与本机 Git Bash/PowerShell 行为不同。脚本中调用 `node`
  多行逻辑优先用 heredoc/stdin，不用多行 `node -e`；调用 `pnpm.cmd`、
  `npm.cmd`、`.bat` 时要通过 `cmd.exe call` 或现有脚本封装，避免 `spawn`
  在 Windows runner 上失败。
- 涉及构建链、补丁管道或裁剪的改动，优先运行能覆盖对应路径的最小验证：
  `git apply --check`、`bash scripts/gen-removals-patch.sh`、`bash scripts/prepare.sh`、
  `bash scripts/build.sh`（按改动范围选择）。若因环境限制未跑，必须在总结中说明。

## 提交规范：Conventional Commits v1.0.0

所有 commit 必须遵循 [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)：

```
<type>(<scope>): <描述>

[正文（可选）：动机与影响]

[脚注（可选）：BREAKING CHANGE: ... / Co-Authored-By: ...]
```

### type（必选）

| type | 用途 |
| --- | --- |
| `feat` | 新功能（扩展功能、新的裁剪项、新脚本能力） |
| `fix` | 缺陷修复 |
| `docs` | 仅文档变更（docs/、README、本文件） |
| `build` | 构建链与依赖（vscodium 集成、补丁管道、pnpm 依赖） |
| `chore` | 杂项（不影响源码与文档语义的维护） |
| `refactor` | 重构（不改行为） |
| `test` | 测试相关 |
| `ci` | CI 配置 |

### scope（推荐，取本仓库目录/机制名）

`extensions`、`patches`、`removals`、`product`、`scripts`、`docs`、`upstream`
（upstream 专用于版本升级：锁定文件 + 子模块指针变更）。

### 示例

```
feat(extensions): 新增荷载组合计算面板 magic-load-calc
feat(removals): 剥离 tasks contribution（闭包分析已登记）
fix(scripts): init.sh 在 checkout release 后重新暂存子模块 gitlink
docs(plan): 补充 Panel 隐藏方案的设计取舍
build(upstream): 升级至 vscode 1.122.0 / vscodium 1.122.03500
```

### 规则要点

- 破坏性变更：type 后加 `!` 或脚注 `BREAKING CHANGE: <说明>`
  （本仓库中典型场景：removals.json 清单结构变更、脚本接口变更）。
- 描述用中文，简洁祈使句；type/scope 用小写英文。
- 一个 commit 一个逻辑变更；升级 vscode 版本的 lock 文件 + 子模块指针 +
  重做的补丁应在同一个 `build(upstream)` commit 中。
- AI 代理提交时保留其署名脚注（如 `Co-Authored-By: Claude ...`）。

## 环境注意事项

- 脚本必须在 **Git Bash** 中运行。PowerShell 里的 `bash` 是未装发行版的
  WSL 存根，会输出乱码报错——不要用。
- `*.sh` / `*.patch` 强制 LF（`.gitattributes` 已配置），不要改成 CRLF。
- 构建 vscode 用的 Node 版本以 `vscode/.nvmrc` 为准（本机用 nvm4w 切换），
  文档站任意 Node ≥ 18 即可。
- `vscode/` 检出弄脏后重置：`git -C vscode checkout . && git -C vscode clean -fd`。

## 常用命令

| 命令 | 作用 |
| --- | --- |
| `bash scripts/init.sh` | 拉起 vscodium 子模块 + 按锁定 commit 检出 vscode |
| `bash scripts/prepare.sh` | 开发模式叠加：补丁 + 裁剪 + 扩展 + 品牌 |
| `bash scripts/gen-removals-patch.sh` | 从 removals.json 重新生成裁剪补丁 |
| `bash scripts/build.sh` | VSCodium 链发行构建 |
| `bash scripts/release.sh` | 发布新版本：创建 tag + 生成 changelog + 推送 |
| `bash scripts/upgrade.sh <tag>` | 升级上游版本（预检 + 再生成） |
| `pnpm docs:build` | 构建并校验文档站 |
