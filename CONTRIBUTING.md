# Contributing

感谢你帮助改进 DSH Desktop Community。这个分支只接受 macOS 客户端、macOS 构建与
相关文档的修改。

1. 较大的行为或界面改动请先开 Issue 说明设计与影响。
2. 从独立分支提交范围明确的修改。
3. 运行 `./build.sh`，并在 macOS 13 或更高版本上验证应用可以启动。
4. 不要提交凭据、Token、`~/.dsh`、模型权重、`.build`、ZIP 或 DMG。
5. Pull Request 应说明用户可见变化、测试方式，以及是否引入新第三方代码或素材。
6. 不要删除或弱化 [LICENSE](LICENSE) 与 [NOTICE.md](NOTICE.md) 中的上游归属声明。
7. 本地模型启动参数必须通过 `Process.arguments` 传递，不得拼接为 Shell 命令字符串。

DeepSeek Harness 运行时本身的修改应提交到其
[上游项目](https://github.com/deepseek-ai/deepseek-harness)。
