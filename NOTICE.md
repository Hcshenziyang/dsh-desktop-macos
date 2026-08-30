# Notices and attribution

## Upstream project

This repository is a modified fork of:

- Project: `frankfika/dsh-desktop-macos`
- Upstream URL: <https://github.com/frankfika/dsh-desktop-macos>
- Fork baseline: commit `7bf53cd9b14e5cf4861f92f46157bfd8e7ba150a`
- Original copyright: Copyright (c) 2026 Fang Chen
- License: MIT License; the complete text is preserved in [LICENSE](LICENSE)

The original copyright and permission notice must remain in all copies or substantial
portions of the software. Subsequent modifications are Copyright (c) 2026 dramtea and
contributors, where applicable, and are distributed under the same MIT License.

`Resources/AppIcon.icns` was generated from the upstream project's MIT-licensed icon
source and remains covered by the attribution and license above.

## Scope of this fork

This fork focuses exclusively on the macOS desktop application. The upstream Android,
iOS, and Windows clients were removed. Removal of those platform directories does not
remove or alter the upstream attribution or license obligations for the retained code.

## Independent project

This is an independent community project. It is not affiliated with, sponsored by,
endorsed by, or an official product of DeepSeek, DeepSeek Harness, or the upstream author.
The names “DeepSeek” and “DSH” are used only to identify compatibility and interoperability.
No trademark rights are granted by the MIT License. All trademarks belong to their
respective owners.

## Separate software and data

DeepSeek Harness is a separate project and may be installed independently from the
`@deepseek-ai/dsh` npm package under its own license and third-party notices. This repository
does not include model weights, API credentials, user conversations, or local `~/.dsh` data.
At runtime, the archive-management feature can read and, after explicit user confirmation,
modify the current user's local DSH indexes and conversation logs. It does not upload them;
see [SECURITY.md](SECURITY.md) for the backup and Trash behavior.

Before adding third-party source code, fonts, icons, images, or other assets, contributors
must verify redistribution rights and record the applicable license and attribution here.
