# DSH Desktop Community for macOS

一个独立维护、专注 macOS 的 DSH 桌面客户端社区项目。在同一个项目中浏览资料、管理待办
与便签、整理长期记忆，也可以随时打开对话，继续编码或让 AI 协助工作。

应用使用 SwiftUI 与 WKWebView，负责管理本机的 `dsh web` 服务，在 DeepSeek Harness
原有界面上增加项目视图与桌面功能。首个公开版本为 [`v0.1.0`](CHANGELOG.md#010---2026-09-01)。

> [!IMPORTANT]
> 本项目是从 [frankfika/dsh-desktop-macos](https://github.com/frankfika/dsh-desktop-macos)
> 演进而来的独立维护衍生项目，基于上游提交
> [`7bf53cd`](https://github.com/frankfika/dsh-desktop-macos/commit/7bf53cd9b14e5cf4861f92f46157bfd8e7ba150a)。
> 它不是 DeepSeek、DeepSeek Harness 或原作者的官方产品，也未获得这些主体的隶属、
> 认可或背书。从 `v0.1.0` 起，本项目拥有自己的名称、版本、路线图、仓库和发布流程；
> Android、iOS 和 Windows 客户端已经移除。独立维护不改变保留代码的 MIT 许可、原作者
> 版权和来源声明义务。

## 功能

- **项目双视图**：传统视图保留对话与编码；文件夹视图浏览资料，随时展开项目对话和历史。
- **Markdown 阅读与编辑**：大面积阅读、独立编辑页、保存与返回；其他文件使用系统默认应用打开。
- **待办与便签**：每个工作区独立管理，用户与 Agent 共用数据，对话自动带入当前摘要。
- **定时任务**：单次、每天或每周执行，可加入待办提醒，也可触发 AI 并保留独立的结果对话。
- **项目记忆**：查看和编辑简要记忆、长期记忆，支持分类、标签、搜索、归档与恢复。
- **运行与本地模型管理**：发现、启动、停止和重启 DSH，支持登录时启动、日志与自定义模型服务脚本。
- **插件与会话管理**：检查 DSH 插件状态和更新，备份恢复插件环境，管理已归档会话。
- **主题与检查器**：十一套内置主题、自定义强调色和壁纸；按需检查实际系统提示、工具与 Skill 目录。
- **原生 macOS 应用**：支持 Apple Silicon 与 Intel Mac，可发现已有 DSH 或协助安装官方运行时。

## 从项目开始

打开或创建一个项目后，根据当前要做的事选择入口：

| 要做的事 | 入口 |
| --- | --- |
| 浏览项目文件和资料 | 项目顶部 → 文件夹 |
| 阅读或编辑 Markdown | 文件夹中点击 `.md` / `.markdown` 文件 |
| 管理事项、便签和定时任务 | 文件夹页 → 待办 / 便签 / 定时任务 |
| 查看与整理项目记忆 | 项目顶部 → 记忆，两种视图均可使用 |
| 与 AI 对话或查看历史 | 文件夹页右侧 → 对话 / 历史，或切换传统视图 |

项目记忆需要启用 `dsh-native-memory`；其他项目工具随客户端提供。更新客户端后重新启动
由客户端管理的 DSH 服务，即可加载新增功能。定时任务只在 DSH 运行时执行，不会唤醒 Mac。

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

## 版本与发布

最近发布版本为 `v0.1.2`，应用内部版本为 `0.1.2 (12)`。本页按 `main` 分支源码描述功能；
项目双视图、Markdown 编辑、工作区工具与项目记忆编辑尚未发布新的版本包，可从源码构建体验。
项目使用语义化版本号；推送 `v*`
标签会触发 macOS 通用版构建，并在本仓库创建对应的 GitHub Release。各版本变化见
[CHANGELOG.md](CHANGELOG.md)。

当前仓库不提供指向上游发布包的自动安装脚本，避免本项目与上游二进制混淆。
准备公开发布前请完成 [发布检查清单](PUBLISHING.md)。

## 项目视图

选中项目后，主内容区顶部可以切换“传统视图 / 文件夹”。传统视图保留原有对话、编码与
工具界面；文件夹视图展示该项目的实际文件，支持逐层浏览、面包屑、当前目录搜索、图标 /
列表排列、隐藏文件开关，以及 Finder 入口。Markdown 文件在完整主区域阅读，支持标题、
列表、表格、引用、代码块和项目内图片；点击“编辑”进入独立编辑页，提供保存、返回阅读、
返回文件夹，以及 ⌘S 保存。其他文件直接交给系统默认应用。右侧“对话 / 历史”展开同一项目的
对话面板；窄窗口采用覆盖式抽屉，宽窗口并排展示文件与对话。

两种视图共用原有项目和会话；项目选择、侧栏和历史列表继续由 DSH 管理。切换视图不会
重新创建会话或卸载对话界面，未发送草稿保留。每个项目独立记住视图偏好，首次默认传统
视图。返回文件夹视图时保留本次窗口中的目录位置，重新启动后从项目根目录开始。

功能作为独立 `ProjectViewsFeature` 模块，在客户端启动 DSH 时通过临时 `--patch` 挂载。
更新客户端后需重新启动由客户端管理的 DSH；外部实例需自行停止后再由客户端启动。普通
浏览器仍显示原有界面。文件读取通过仅限本机同源主页面的 WebKit 通道完成，根目录来自
现有 Workspace 索引，阻止上级路径及指向项目外的链接。DSH 若更改布局且无法识别，保留
原始界面。当前只支持本机 DSH 和默认的 JSON Workspace 索引。

Markdown 编辑仅支持不超过 2 MB 的 UTF-8 `.md` / `.markdown` 文件；保存比较原文件版本，
文件被其他应用或 Agent 修改时拒绝覆盖。保存保持原有 UTF-8 BOM、换行格式及文件权限。
未保存草稿按项目和文件暂存在本机 WebKit 存储中，返回文件夹或重开客户端后可恢复；草稿
不会写入项目文件，需点击“保存”才能落到原文。清除客户端网站数据会清除这份草稿缓存。

Markdown 使用随包提供的 markdown-it 排版，禁用原始 HTML，不执行文档脚本。项目内图片
通过本机受限读取显示；远程图片提供手动打开入口。文档链接可打开同项目 Markdown 或系统
默认应用，网页链接在默认浏览器打开。

## 项目记忆

项目顶部的“记忆”入口在传统视图和文件夹视图中均可使用，以大尺寸页面展示和编辑当前
项目的记忆。“简要记忆”是记忆插件带入对话的少量背景；“长期记忆”支持分类、标签、
搜索、编辑、归档与恢复，供 Agent 按需检索。原有“固定输入与记忆”检查器继续用于查看
实际请求和全部项目的数据。

`ProjectMemoryFeature` 负责本机认证传输，`Resources/ProjectMemory` 独立适配已启用的
`dsh-native-memory` v1 storage-domain。读写直接使用插件打开的同一个域和串行写入队列，
不会生成第二份记忆库，也不会从 Swift 改写 `dsh_memory.json`。仅首次读取时调用只读的
`memory_profile` 初始化原插件；页面保存不调用模型，Agent 自己写记忆时仍走原有审批。
数量和字数上限沿用当前插件配置。手动编辑标记为 `desktop-editor`，不伪造对话来源。

项目范围由服务端 Workspace 注册表解析，沿用记忆插件按工作目录隔离的语义；同一目录
对应的多个项目共享记忆，页面会提示。已有记录在写入队列内核对版本，冲突时保留草稿。
项目的 Agent 正在运行或等待审批时，手动保存会暂缓，防止覆盖其待提交修改。草稿只保留
在当前窗口中，返回项目和切换项目不会丢失；退出应用或重载页面前请保存。

首次打开记忆需要该项目已打开过一次对话。插件未启用或格式不兼容时显示明确提示。
可运行 `./scripts/test-memory-runtime.sh` 验证真实插件双向读写、提示词更新、项目隔离、
冲突保护、归档恢复和重启持久化；测试使用独立 DSH_HOME 和本地模拟模型。

## 工作区待办、便签与定时任务

文件夹页提供同级的“待办 / 便签 / 定时任务”，可收起工具区以留出文件浏览空间。
待办支持状态、截止日期和说明；便签支持正文与置顶；三类内容均可归档、恢复。
同一工作区的所有对话共享这些内容，其他工作区互相隔离。

Agent 的每次模型请求自动附带当前待办和便签摘要；需要全文时使用 `workspace_note_read`，
通过 `workspace_tools_list` 和 `workspace_todo_*`、`workspace_note_*` 工具读取或修改。
用户与 Agent 共用一份数据，更新检查条目版本，避免互相覆盖。编辑草稿不会被后台刷新替换；
遇到冲突可核对列表、复制草稿，或用“放弃草稿并重载”重新编辑。DSH 原有 `todo_write` 仍是
会话内部的执行计划，与这里的个人待办独立。

定时任务支持单次、每天、每周，可选择加入待办的提醒或 AI 执行。AI 使用创建任务时对话的
模型与 Agent 预设，新建独立对话，沿用 DSH 的操作确认机制。可暂停、恢复、运行一次、查看
最近执行记录，并直接打开结果对话。编辑暂停任务不会自动启用它；手动运行不会改变下次时间。

定时器只在由客户端启动的 DSH 服务运行时工作，不会唤醒休眠的 Mac。恢复服务后，错过的周期
只补执行一次；中断的 AI 运行记为中断，避免自动重复操作。最多同时执行两个 AI 定时任务，
提醒不占用这一额度。重复时间按创建时保存的时区计算。

`WorkspaceToolsFeature` 仅负责本机通道，独立 DSH 扩展负责数据和执行。数据保存在
`DSH_HOME/desktop/workspace-tools.json`（默认 `~/.dsh/desktop/workspace-tools.json`），不写入项目仓库。
同一数据目录只允许一个服务写入；原子落盘、条目版本和运行记录用于处理并发及异常退出。
这是项目的当前工作数据，长期记忆仍由既有记忆模块管理。

执行 `scripts/test.sh` 检查模块边界及功能回归；可另运行 `scripts/test-workspace-runtime.sh`
进行真实 DSH 联调。后者使用隔离数据与本地模拟模型，覆盖工具读写、上下文注入、版本冲突、
认证和定时 AI 对话，不需要模型凭据。

## 本地模型服务

工具栏提供通用的本地模型图标按钮；鼠标悬停会显示模型名称、状态和当前动作。首次使用时
在“设置 → 本地模型服务”中配置：

- 显示名称，例如 `Qwen 27B`、`MLX Server` 或 `Ollama`
- 启动程序：可执行文件，或具有执行权限并包含正确 shebang 的脚本
- 启动参数：使用普通命令行写法，路径含空格时可使用单双引号
- 停止程序与停止参数：可选；启动脚本会转为后台服务时建议配置
- 健康检查 URL：可选，例如 `http://127.0.0.1:8000/health`
- 退出应用时是否停止本地模型

例如，已有 `start.sh` / `stop.sh` 的本地模型服务可以配置为：

```text
名称:       本地模型
启动程序:   ~/LocalModels/start.sh
停止程序:   ~/LocalModels/stop.sh
健康检查:   http://127.0.0.1:8000/health
```

应用使用 `Process` 直接执行所选程序，并把参数作为数组传递，不交给 Shell 解释。因此不
支持 `|`、`&&`、重定向、环境变量展开或 `$()` 命令替换。所选程序拥有当前 macOS 用户的
权限，只应配置自己编写或已确认可信的程序。仓库不会附带、下载或分发模型权重。

健康检查只有收到 HTTP `2xx` 或 `3xx` 才会判定模型就绪。`4xx`/`5xx` 会显示具体状态码和
“端口可能被其他服务占用”，连接失败则按启动超时或连续失败处理，避免其他本地服务碰巧占用
同一端口时把按钮错误显示为“模型已就绪”。

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
列表仍可使用。可以在客户端“设置”中关闭“简化内嵌 Web UI 的插件列表”。

## 插件管理与更新

工具栏的拼图按钮打开原生“插件管理”窗口，显示 Web profile 中用户插件的实际安装版本、
版本约束、最新版本和运行状态。“检查更新”使用本机 pnpm 和当前 registry 配置查询 npm
的 `latest` 标签，逐个显示网络错误。需要已安装 pnpm。Git、本地目录、tarball 和 npm
别名来源暂不提供一键更新，应按原始来源维护。官方内置组件随 DSH 运行时升级。

确认“更新”后，客户端停止自己管理的服务，备份整个 `profiles/web`（包括配置、锁文件和
`node_modules`），执行 `dsh plugin --profile web update 包名@已检查的目标版本`，随后
启动服务并根据 Loader 的实际运行单元检查插件。目标版本可能跨越现有约束。原本停止的
服务也会启动以完成验证；请在会话空闲时操作。外部启动的服务需要先自行停止，操作期间
不要同时在终端管理插件。

完整备份保存在 `~/.dsh/backups/plugin-manager/web/`（遵循 `DSH_HOME`）。安装失败时
不会启动可能不完整的环境；安装、启动或加载验证失败均会保留错误和恢复入口。“恢复”会
将**整个 Web profile** 回到选定备份的状态，恢复前另存当前环境，再启动服务检查。恢复
已复制的插件文件不需要联网；本地链接指向的外部源码不包含在备份中。备份不会自动删除，
可通过窗口内的 Finder 按钮管理其磁盘占用。

运行状态由客户端启动时挂载的只读 Loader 观察模块提供，仅记录模块名、启用状态、加载
阶段、进程 ID 和时间戳，写入用户私有缓存。外部实例或没有该模块的旧实例显示“状态未
验证 / 暂不可用”，从客户端重新启动后即可读取。未知或未发现的运行单元不会被当作加载
成功。

## 主题与壁纸

工具栏的调色盘按钮会打开独立“主题与壁纸”设置。当前支持：

- DSH 原生、松雾、深海和暖砂配色预设
- 十一套完整皮肤：星轨次元、留白秩序、云端软糖、海岬初晓、霓雨协议、猫耳心跳、花火映像、
  诡箓迷城、龙焰秘典、灰烬王庭和方块晴野
- 完整皮肤会共同调整背景、侧栏、消息气泡、输入框、按钮、悬停/选中态、文字层级、代码块、
  滚动条、阴影、字体倾向，以及 macOS 原生工具栏和管理窗口
- 弹窗、错误/成功状态、快捷图标、圆角与玻璃模糊使用同一主题参数；十一套皮肤分别提供星轨、
  纸面、浮泡、海雾、霓雨、猫爪星糖、花影、诡墨、龙焰、灰烬和像素动效，并遵循
  macOS“减少动态效果”设置
- 软边、霓虹、缝线、花影、诡箓、秘法双线、风化和像素硬边组成独立框体系统，覆盖会话卡片、
  工作区、输入框、菜单、代码块、状态提示和确认弹窗
- 会话历史与工作区分组使用主题化卡片、轮换小图标、选中边框和悬停动画；搜索结果、列表选项
  与插件卡片也会获得一致但更轻的反馈
- 自定义强调色，并同步应用到 Web UI 语义色与客户端原生控件
- PNG、JPEG、HEIC、WebP、TIFF 静态壁纸，单个文件最大 50 MB
- 填充、适应、居中和平铺显示方式
- 壁纸模糊、暗化和面板不透明度实时调节
- 一键关闭全部增强或恢复 DSH 原生外观

主题模块不会修改 DSH 核心、Web profile 或 `node_modules`。它以 DSH 的 `--dsw-*` 语义
颜色令牌为边界，同时为浅色和深色状态生成覆盖值，因此 DSH 切换外观时无需重启。每套内置
主题都是一个独立、数据驱动的目录：

```text
Resources/Themes/<theme-id>/
├── theme.json       完整浅/深配色、字体、动效、图标、框体与壁纸参数
├── wallpaper.png    该主题独享的原创素材
└── CREDITS.md       素材来源和生成提示词
```

内置主题不能跨目录引用素材。十一张内置壁纸均为本项目使用 OpenAI ImageGen 原创生成，没有
抓取网络图片或使用外部参考图；人物均为虚构成年人，题材主题不包含现实公众人物肖像或现有
作品的角色、Logo 和提取纹理。用户自己选择的壁纸则以随机文件名复制到：

```text
~/Library/Application Support/io.github.dramtea.dsh-desktop-community/Themes/
```

WKWebView 通过客户端私有的 `dsh-desktop-theme://` 资源通道读取内置主题或用户副本；页面
看不到原始图片路径，DSH HTTP 服务也无法通过该通道读取其他文件。移除自选壁纸或恢复默认
只会删除客户端副本，不修改用户选择时的原始图片。壁纸和配置不会上传。

## 模型固定输入与长期记忆

工具栏的脑形按钮会打开原生“模型固定输入与记忆”窗口。它不重复 DSH“轨迹”已有的对话、
工具调用和执行过程，而是按每次实际 Assistant 请求展示：

- 最终实际发送的 System Prompt，以及 DSH 注册表中组成它的具名提示词段
- Provider Adapter 收到的完整工具目录、说明和参数 Schema
- 最终请求中最新的 `skill-catalog`：Skill 名称、说明和实际发送的目录原文
- `AGENTS.md` 工作区指令与本轮已经显式加载的 Skill 正文
- System Prompt 中本次实际注入的 `<memory-profile>`

普通用户对话、模型回复、工具调用、工具结果、上下文压缩过程和标题生成不会写入检查器
缓存。Skill 目录在 DSH 中实际是一条持久的用户角色 `<system-reminder>`，并不属于 System
Prompt 或工具执行轨迹；客户端依据它的 `skill-catalog` 来源元数据识别当前有效目录。

应用不会修改 DSH 核心或用户 profile。由本客户端启动 DSH 时，它通过一次性的
`dsh web --patch` 挂载随应用打包的只读观察插件，在 `system-prompt/assemble` 与
`llm/stream` 边界读取最终固定输入。最近 32 次请求保存在当前用户的 macOS Caches 目录，文件权限为 `0600`，正常停止
客户端托管的 DSH 时会删除；下次启动也会先清除残留缓存。适配器私有的 `replayState`、
取消信号和服务商凭据不会写入。可以在“设置”中关闭捕获，修改后需重启 DSH。

外部启动的 DSH 没有自动挂载该观察插件，因此客户端会提示先停止外部实例并从客户端
重新启动。该页面展示的是 DSH 交给 Provider Adapter 的固定语义输入；适配器随后生成的
厂商专用 HTTP JSON 可能具有不同字段布局。

长期记忆页只读展示 `dsh-native-memory` 的 `~/.dsh/storages/dsh_memory.json`：

- 每个工作区自动注入 System Prompt 的 Profile
- 活跃及已归档 Facts、类型、标签、时间和来源会话序号
- 所选模型请求是否实际注入了该工作区的 Profile

Agent 的记忆写入、编辑和遗忘通过 `memory_remember`、`memory_edit`、`memory_forget` 完成，
沿用插件的人工审批流程。用户也可在项目顶部的“记忆”页面直接编辑同一份数据。
若设置了 `DSH_HOME`，检查器会读取对应数据目录。

## 项目结构

```text
Sources/App/                 应用生命周期、窗口与功能组装
Sources/Core/Runtime/        DSH 运行时、启动准备与维护协调
Sources/Core/System/         进程、命令、路径和日志等系统能力
Sources/Core/Web/            通用 WebKit 容器（独立 DSHWeb 模块）
Sources/UI/                  共用主题、控件与 Web 主题渲染
Sources/Features/LocalModel/ 本地模型服务、设置与工具栏入口
Sources/Features/Archive/    归档模型、磁盘操作、状态与界面
Sources/Features/Inspector/  固定输入与记忆的读取、观察器和界面
Sources/Features/Plugins/    DSH 插件管理、状态观察与 Web 增强
Sources/Features/Themes/     主题设置界面
Sources/Features/ProjectViews/ 项目视图、文件读取及本机桥接
Sources/Features/WorkspaceTools/ 工作区工具启动与本机传输
Sources/Features/ProjectMemory/ 项目记忆启动与本机传输
Package.swift                构建、测试与编辑器共用的模块依赖图
Tests/                       功能行为和模块边界回归测试
Resources/RequestInspector/  请求观察模块资源
Resources/PluginInventory/   插件状态观察模块资源
Resources/ProjectViews/      文件夹视图、样式与 DSH 布局适配
Resources/WorkspaceTools/    工作区工具界面、共享存储及定时执行
Resources/ProjectMemory/     项目记忆界面、原插件存储适配
Resources/Themes/            独立主题包与素材
build.sh                     通用 macOS App 构建、资源组装和签名
scripts/test.sh              依赖边界、Swift 与 Node 回归检查
scripts/package.sh           ZIP、DMG 与校验文件打包
script/build_and_run.sh       本地构建、启动和调试
.github/workflows/           CI 与 Release 工作流
```

这些是客户端内部模块。当前没有动态加载或安装客户端插件的框架；`Plugins` 管理的是
DSH 运行时插件。功能之间不直接依赖，由 `AppContainer` 组装，模块依赖在 `Package.swift`
中显式声明。

## 开发与验证

| 检查 | 命令 | 范围 |
| --- | --- | --- |
| 模块与功能回归 | `./scripts/test.sh` | 模块依赖、Swift 测试、界面脚本与数据行为 |
| 工作区工具联调 | `./scripts/test-workspace-runtime.sh` | 待办、便签、上下文共享与定时 AI 对话 |
| 记忆插件联调 | `./scripts/test-memory-runtime.sh` | 项目隔离、双向读写、修改冲突与重启持久化 |
| 应用构建 | `./build.sh` | Apple Silicon / Intel 通用应用与签名检查 |
| 应用启动 | `./scripts/smoke-app.sh` | 构建后的应用在隔离环境中启动 |

联调脚本需要本机已安装 DSH；记忆联调还需要 `dsh-native-memory`，可通过
`DSH_MEMORY_MODULE` 指定其模块文件。联调使用临时数据目录与本地模拟模型，不调用付费模型。
`docs/` 用于本地工作记录和验证结果，已加入 `.gitignore`；构建产物、缓存与用户数据不提交。

## 来源、许可与商标

- 原始项目代码版权归 Fang Chen 所有，依据 [MIT License](LICENSE) 使用和再发布。
- 本项目保留完整 Git 历史、原始版权声明和许可文本；修改部分由相应贡献者持有版权。
- DeepSeek Harness 是独立项目，通过官方 `@deepseek-ai/dsh` npm 包单独安装；本仓库不
  包含它的源码、模型权重或用户凭据。
- “DeepSeek”“DSH”及相关名称仅用于说明兼容对象。MIT 许可不授予任何商标权。

详情见 [NOTICE.md](NOTICE.md)。

## License

本项目依据 [MIT License](LICENSE) 发布。保留原始版权与许可声明是复制、修改或分发
本项目的条件。

---

## English summary

DSH Desktop Community is an independently maintained, macOS-only derivative of
[frankfika/dsh-desktop-macos](https://github.com/frankfika/dsh-desktop-macos). It is an
independent community project and is not affiliated with, endorsed by, or an official
product of DeepSeek, DeepSeek Harness, or the upstream author. The upstream copyright and
MIT license are preserved. Beginning with `v0.1.0`, this project has its own name,
versioning, roadmap, repository, and release process. DeepSeek Harness is installed
separately; this repository does not distribute model weights or credentials. See
[NOTICE.md](NOTICE.md) for attribution and trademark information.

The `main` branch adds per-project conversation and folder views, a Markdown reader
and editor, shared todos and notes, scheduled reminders or AI tasks, and an editor
for the existing `dsh-native-memory` store. These additions are available from source
and are not yet included in a new release package. Other file types open in their
default macOS applications. Runtime plugins and client features remain separate;
the client does not yet provide a dynamic client-plugin framework.
