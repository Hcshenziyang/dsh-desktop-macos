# Contributing

感谢你帮助改进 DSH Desktop Community。本项目只接受 macOS 客户端、macOS 构建与
相关文档的修改。

1. 较大的行为或界面改动请先开 Issue 说明设计与影响。
2. 从独立分支提交范围明确的修改。
3. 运行 `./scripts/test.sh` 和 `./build.sh`，并在 macOS 13 或更高版本上验证应用可以启动。
4. 不要提交凭据、Token、`~/.dsh`、模型权重、`.build`、ZIP 或 DMG。
5. Pull Request 应说明用户可见变化、测试方式，以及是否引入新第三方代码或素材。
6. 不要删除或弱化 [LICENSE](LICENSE) 与 [NOTICE.md](NOTICE.md) 中的上游归属声明。
7. 本地模型启动参数必须通过 `Process.arguments` 传递，不得拼接为 Shell 命令字符串。
8. Web 主题优先覆盖 DSH 的 `--dsw-*` 语义令牌；新增 DOM 选择器时必须提供失配后的安全
   回退，并验证浅色、深色与无壁纸状态。
9. 内置主题必须独占 `Resources/Themes/<theme-id>/`，目录名与 `theme.json` 的 `id` 一致；
   壁纸不得跨目录引用，并应在同目录 `CREDITS.md` 记录来源、许可或生成方式。
10. schema v3 主题应同时验证环境动效和 `frame` 框体在 SwiftUI/WebKit 两侧的退化行为；人物
    素材只能使用虚构成年人，题材主题不得打包公众人物肖像或现有作品的提取素材。

DeepSeek Harness 运行时本身的修改应提交到其
[上游项目](https://github.com/deepseek-ai/deepseek-harness)。

完整回归检查运行 `./scripts/test.sh`（Swift 6+ 工具链、Python 3、Node.js）。
脚本先检查模块依赖，再运行 Swift Testing 与 Node 测试；数据写入仅使用临时目录和独立
测试偏好域。覆盖设置隔离、维护互斥、归档数据兼容、主题资源，以及插件的版本识别、离线
恢复、互斥锁、命令参数与退出码、大量输出和子进程超时清理。服务功能测试在回环地址运行
临时 HTTP 子进程，验证启停、重启、外部实例接入，以及本地模型健康检查的失败和恢复。
`./scripts/test-plugins.sh` 保留为插件测试入口。若默认 SDK 与工具链不兼容，可以通过
`SDKROOT` 指定兼容 SDK；构建与测试共用工具链配置。

功能之间不得直接导入或寻找全局实例；新增功能由 `AppContainer` 组装，依赖必须在
`Package.swift` 显式声明。
