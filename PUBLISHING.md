# Public release checklist

发布本项目的新版本或二进制前：

- [ ] 保留 `LICENSE` 原文以及 `NOTICE.md` 中的原作者、上游链接和衍生基线。
- [ ] 确认仓库说明和 Release 页面明确标注“独立维护的社区衍生项目、非官方、无背书”。
- [ ] 确认 App 名称、Bundle ID、图标与发布者身份不会让用户误认为上游或官方版本。
- [ ] 把 GitHub `origin` 设置为你自己的仓库；保留 `upstream` 指向原项目。
- [ ] 确认 README 的克隆地址和下载链接都指向
      `https://github.com/Hcshenziyang/dsh-desktop-macos`，而不是上游 Release。
- [ ] 确认 Git 标签、`Info.plist` 应用版本和 `CHANGELOG.md` 版本一致。
- [ ] 启用 GitHub Private vulnerability reporting，并提供维护者的私密联系方式。
- [ ] 检查新增代码、字体、图标、图片及其他素材的许可，将必要声明加入 `NOTICE.md`。
- [ ] 执行秘密扫描，确认没有 API Key、Token、证书、签名私钥、`.env`、`~/.dsh` 或聊天数据。
- [ ] 核对归档管理的数据处理说明、删除确认、索引备份与废纸篓恢复行为仍与实现一致。
- [ ] 用当前受支持的 DSH 版本核对插件列表增强依赖的 `data-plugin-entry`、`data-phase` 与
      `data-enabled` DOM 标记；结构不匹配时应无害回退到原始列表。
- [ ] 确认没有提交模型权重、个人绝对路径、`.build`、缓存、DMG 或 ZIP。
- [ ] 运行 `./build.sh` 和 `./scripts/package.sh`，核对产物中的版本、版权和许可证。
- [ ] 面向普通用户分发时，使用自己的 Apple Developer ID 签名并完成 notarization；如仍为
      ad-hoc 签名，应在 Release 页面清楚说明。
- [ ] 在每个 Release Notes 中概括相对上游的实质修改和已知限制。

此清单用于降低常见的许可、归属、品牌混淆和隐私风险，不构成法律意见。
