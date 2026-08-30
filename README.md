# DSH Desktop Community for macOS

一个专注 macOS 的 DSH 桌面客户端社区分支。应用使用 SwiftUI 与 WKWebView，负责发现、
启动、停止和重启本机的 `dsh web` 服务，并在原生窗口中显示 DeepSeek Harness Web UI。

> [!IMPORTANT]
> 本仓库是 [frankfika/dsh-desktop-macos](https://github.com/frankfika/dsh-desktop-macos)
> 的修改分支，基于上游提交
> [`7bf53cd`](https://github.com/frankfika/dsh-desktop-macos/commit/7bf53cd9b14e5cf4861f92f46157bfd8e7ba150a)。
> 它不是 DeepSeek、DeepSeek Harness 或原作者的官方产品，也未获得这些主体的隶属、
> 认可或背书。Android、iOS 和 Windows 客户端已从本分支移除。

## 功能

- 原生 SwiftUI + WebKit macOS 应用，不引入第三方 App 依赖
- 同时支持 Apple Silicon 与 Intel Mac
- 检测已有 `dsh web` 服务，或从应用中启动、停止和重启服务
- 在浏览器中打开、登录时启动、实时日志和常用运行控制
- 检测 Homebrew、npm、nvm、WorkBuddy 及常见 DSH 安装位置
- 缺少运行时时，可单独安装官方 npm 包 `@deepseek-ai/dsh`
- 可配置的本地模型服务按钮，可启动和停止用户选择的程序或脚本
- 原生归档管理，可查看、恢复、逐条删除或清空 DSH 已归档会话
- 简化内嵌插件列表，默认聚焦用户安装和异常运行单元，官方组件保留在高级视图

## 系统要求

- macOS 13 Ventura 或更高版本
- Node.js 22.19+ 或 24+
- `@deepseek-ai/dsh`（应用可协助单独安装）

DeepSeek Harness 可能读取或修改你选择的工作目录。首次使用建议选择临时项目、使用
受限凭据，并认真检查每次权限请求。不要把 DSH Web 服务直接暴露到公网。

## 从源码构建

安装 Xcode Command Line Tools 后运行：

```bash
git clone https://github.com/Hcshenziyang/dsh-desktop-macos.git
cd dsh-desktop-macos
./build.sh
open ".build/DSH Desktop Community.app"
```

默认生成 Apple Silicon 与 Intel 通用版本。只构建当前架构：

```bash
ARCHS="$(uname -m)" ./build.sh
```

创建 ZIP、DMG 和 SHA-256 校验文件：

```bash
./scripts/package.sh
```

当前仓库不提供指向上游发布包的自动安装脚本，避免社区分支与上游二进制混淆。
准备公开发布前请完成 [发布检查清单](PUBLISHING.md)。

## 本地模型服务

工具栏提供通用的“启动模型 / 停止模型”按钮。首次使用时在“设置 → 本地模型服务”中
配置：

- 显示名称，例如 `Qwen 27B`、`MLX Server` 或 `Ollama`
- 启动程序：可执行文件，或具有执行权限并包含正确 shebang 的脚本
- 启动参数：使用普通命令行写法，路径含空格时可使用单双引号
- 停止程序与停止参数：可选；启动脚本会转为后台服务时建议配置
- 健康检查 URL：可选，例如 `http://127.0.0.1:8000/health`
- 退出应用时是否停止本地模型

例如，已有 `start.sh` / `stop.sh` 的 Qwen 服务可以配置为：

```text
名称:       Qwen 27B
启动程序:   ~/Qwen38-27B-DSH/start.sh
停止程序:   ~/Qwen38-27B-DSH/stop.sh
健康检查:   http://127.0.0.1:8000/health
```

应用使用 `Process` 直接执行所选程序，并把参数作为数组传递，不交给 Shell 解释。因此不
支持 `|`、`&&`、重定向、环境变量展开或 `$()` 命令替换。所选程序拥有当前 macOS 用户的
权限，只应配置自己编写或已确认可信的程序。仓库不会附带、下载或分发模型权重。

## 归档管理

当前 DSH 的“归档会话”只会隐藏会话，Web UI 暂未提供归档列表、取消归档或永久删除入口。
本客户端在工具栏提供原生归档管理按钮，用于：

- 查看 `~/.dsh` 中的归档会话、工作目录、更新时间和日志大小
- 恢复会话（仅移除归档标记，不改动日志）
- 永久删除单条会话，或清空全部归档

为避免运行中的 DSH 把内存状态重新写回磁盘，恢复和删除只会在 DSH 服务停止时启用。
删除操作不会直接擦除日志：客户端先把 `workspace.json` 与
`session_projcache.json` 备份到 `~/.dsh/backups/archive-manager/`，再将对应 JSONL
会话目录移到 macOS 废纸篓，并清理工作区、归档集合和摘要缓存中的引用。用户在清空废纸
篓前仍可找回日志。如果设置了 `DSH_HOME`，客户端会改用该数据目录。

## 插件列表简化

DSH Web 的“插件列表”实际展示的是 Cordis Loader 的全部运行单元，官方会话、模型、工具和
Web UI 组件也会平铺在同一列表中。客户端默认对**内嵌 Web UI** 增加一层纯展示筛选：

- **用户安装**：读取 `~/.dsh/profiles/web/package.json` 的 `dependencies`，只显示这些
  Bundle 贡献的运行单元
- **异常 / 等待**：集中显示挂载失败、等待依赖、加载中或正在卸载的单元
- **全部运行单元**：保留 DSH 原始完整清单，作为高级诊断视图

该功能只操作 WKWebView 中已经渲染的 DOM，不修改 DSH 核心、profile 配置或
`node_modules`。它依赖上游插件卡片公开的 `data-plugin-entry`、`data-phase` 和
`data-enabled` 属性；如果未来 DSH 改变界面结构，增强层找不到这些标记时会停止处理，原始
列表仍可使用。可以在客户端“设置”中关闭“简化内嵌 Web UI 的插件列表”。通过“系统浏览器”
打开 DSH 时仍显示上游原始界面。

## 项目结构

```text
Sources/DSHLauncherApp.swift  应用入口与 macOS 生命周期
Sources/Manager.swift         DSH、本地模型与进程管理
Sources/MainViews.swift       主界面与设置界面
Sources/Archive.swift         归档数据、管理逻辑与界面
Sources/WebView.swift         内嵌 Web UI 与插件列表增强
Package.swift                 SwiftPM 模块描述，用于编辑器索引与跨文件跳转
.sourcekit-lsp/config.json    SourceKit-LSP 索引配置
Resources/AppIcon.icns        App 图标资源
Info.plist                    macOS Bundle 元数据
build.sh                      通用 macOS App 构建脚本
script/build_and_run.sh       本地构建、启动和调试入口
scripts/package.sh            ZIP、DMG 与校验文件打包脚本
.github/workflows/            macOS CI 与 Release 工作流
```

## 来源、许可与商标

- 原始项目代码版权归 Fang Chen 所有，依据 [MIT License](LICENSE) 使用和再发布。
- 本分支保留完整 Git 历史、原始版权声明和许可文本；修改部分由相应贡献者持有版权。
- DeepSeek Harness 是独立项目，通过官方 `@deepseek-ai/dsh` npm 包单独安装；本仓库不
  包含它的源码、模型权重或用户凭据。
- “DeepSeek”“DSH”及相关名称仅用于说明兼容对象。MIT 许可不授予任何商标权。

详情见 [NOTICE.md](NOTICE.md)。

## License

本项目依据 [MIT License](LICENSE) 发布。保留原始版权与许可声明是复制、修改或分发
本项目的条件。

---

## English summary

DSH Desktop Community is a macOS-only derivative of
[frankfika/dsh-desktop-macos](https://github.com/frankfika/dsh-desktop-macos). It is an
independent community project and is not affiliated with, endorsed by, or an official
product of DeepSeek, DeepSeek Harness, or the upstream author. The upstream copyright and
MIT license are preserved. DeepSeek Harness is installed separately; this repository does
not distribute model weights or credentials. See [NOTICE.md](NOTICE.md) for attribution and
trademark information.
