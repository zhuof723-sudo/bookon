# BookOn

iOS 网络小说阅读器，使用 Swift / SwiftUI 重写，功能参考 [Legado](https://github.com/gedoor/legado)。

## 构建
本项目无需本地 Mac：推送到 `main` 后 GitHub Actions 自动编译并生成**未签名 IPA**，
在 Releases 页面下载，使用 AltStore / Sideloadly / TrollStore 自签安装。

- 工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 根据 `project.yml` 生成
- 最低系统：iOS 16

## 路线图
- [x] 0. 工程骨架 + 云端打包
- [ ] 1. 数据模型（兼容 Legado 书源 JSON）+ 本地存储
- [ ] 2. 书源导入（URL / 剪贴板 / 文件）与管理
- [ ] 3. 网络层 + URL 规则解析
- [ ] 4. 规则引擎（CSS / XPath / JSONPath / 正则 / JS）
- [ ] 5. 搜索 → 详情 → 目录 → 正文
- [ ] 6. 书架 + 阅读器（分页、翻页、主题）
- [ ] 7. 本地 TXT / EPUB
- [ ] 8. 替换净化、朗读、WebDAV 备份

## License
GPL-3.0
