# 许可证与第三方声明

## dx-macro 本身

Copyright (C) 2026 aki274415919

本项目自己的代码（`main.ahk`、`config.ahk`、`lib/Backends.ahk`、`selftest.ahk`、
`build-release.ps1` 及文档）以 **GPL-3.0** 授权，见 [`LICENSE`](LICENSE)。

## 一句话结论

**个人 / 非商业使用完全免费。** 唯一的收费点来自下面的 Interception 驱动：
**商业使用需要向 Interception 作者购买商业授权**——这由该驱动的许可证决定，与本项目的
许可证无关。不用硬输入（`#DxHardInput off`，纯 SendInput）时不涉及 Interception，无此限制。

## 用到的第三方组件

这些组件**不在本仓库里**（被 `.gitignore` 排除），使用时自行获取；编译发布包
（`build-release.ps1`）会把其中的运行库打进 `dx-macro.exe` 一起分发。

| 组件 | 作者 | 许可证 | 说明 |
|---|---|---|---|
| AutoHotkey v2（运行时 / 编译 exe 的 base） | AutoHotkey Foundation | **GPL v2** | 运行 / 编译 `.dxm` 所需 |
| AutoHotInterception | Clive Galway (evilC) | **MIT** | C# ↔ 驱动的桥接，最宽松 |
| Interception | Francisco Lopes (oblitum) | **LGPL-3.0（非商业）/ 商业授权（商用）** | 内核键盘驱动 |

### Interception 的双许可证要点

- **非商业使用**：LGPL-3.0，免费。
- **商业使用**：需向作者取得商业授权。见 <https://github.com/oblitum/Interception>。

如果你分发编译好的 `dx-macro.exe`（里面打包了 Interception 运行库），这份分发要连带遵守
Interception 的 LGPL-3.0 / 商业授权条款；AutoHotInterception 的 MIT 要求保留其版权声明；
AutoHotkey 的 GPL v2 适用于其解释器部分。
