# Security policy

## Reporting a vulnerability

请不要为尚未修复的漏洞创建公开 Issue。优先使用本仓库 GitHub **Security** 页面中的
私密漏洞报告功能；如果该功能尚未启用，请通过仓库维护者公开资料中提供的私密联系方式
报告。公开仓库前，维护者应启用 GitHub Private vulnerability reporting。

DeepSeek Harness 运行时的漏洞请报告给其
[上游安全页面](https://github.com/deepseek-ai/deepseek-harness/security)。

## Scope

应用会启动用户选择的 DSH 运行时和可选的本地模型程序，并嵌入 loopback Web UI。这些
程序拥有当前 macOS 用户的权限，因此只应选择来源可信的可执行文件或脚本。本地模型参数
会直接传给 `Process`，不会经过 Shell 解释。本项目不应收集遥测，也不管理模型服务商
凭据。不要把本地 Web 服务直接暴露到不可信网络。

归档管理会读取所选 DSH 数据目录（默认 `~/.dsh`）中的 Workspace 索引、会话摘要缓存
和 JSONL 日志目录。读取归档列表不会修改数据；恢复或删除必须由用户主动触发，并且只在
DSH 服务停止时执行。删除前会把索引备份到 `~/.dsh/backups/archive-manager/`，日志则移
到 macOS 废纸篓而不是直接擦除。索引备份、废纸篓中的日志和原始 `~/.dsh` 数据都可能
包含敏感的对话标题、路径或内容，用户应按自己的保留策略管理它们。客户端不会上传这些
数据。

插件列表简化脚本只在本应用的 loopback WKWebView 主 frame 中运行，读取 Web 页面已经公开
渲染的模块名、启用状态和 Fiber phase，并读取本地 Web profile 的直接依赖包名用于分类。
它不拦截网络请求、不修改 DSH 配置，也不向页面或外部服务发送额外数据。通过系统浏览器
打开的 DSH 页面不受该脚本影响。

“固定输入与记忆”功能会在客户端托管的 DSH 上通过临时 `--patch` 挂载本仓库随附的只读
观察插件。插件读取最终固定输入，但不改写请求或响应；它不会读取或记录 Provider 凭据、
HTTP Authorization Header、取消信号或适配器私有 replay state，也不会保存普通用户
对话、模型回复、工具调用、工具结果、压缩过程或标题生成请求。

捕获内容仍可能包含 System Prompt、工具 Schema、Skill 目录、`AGENTS.md` 工作区指令、
已经加载的 Skill 正文、工作区路径和注入 System Prompt 的长期记忆，因此仍应视为敏感
数据。最近请求仅写入当前用户的 macOS Caches 目录，权限设为 `0600`，正常停止服务时删除，
下次客户端托管启动前也会清除残留文件。用户可在设置中关闭该功能。

长期记忆页面只读访问 DSH 数据目录中的 `storages/dsh_memory.json`，不会绕过
`dsh-native-memory` 的写入审批。客户端不会上传捕获请求或记忆数据。复制到剪贴板后，内容
将受 macOS 剪贴板和用户所用第三方剪贴板工具的保留策略约束。
