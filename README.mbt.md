# hnlyxiaobing/yuv

> 实现完成 · **API 冻结前对账已完成（2026-11-07）**。本包提供中性帧/图像值类型、转换配置与 `to_rgb` / `rotate` / `mirror_x` / `RgbImage::{channels, bytes}` 的**真实实现**，**纯计算、无 I/O**。四道门禁 `moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check`：全绿（35 tests，0 条 `0068`）。**冻结后签名变更即破坏性变更。**

纯计算叶子库：YUV → RGB、旋转、镜像；Frame/Rgb Wire 契约的一端。

完整文档见同目录 `README.md`、`DESIGN.md`、`API.md`、`DECISIONS.md`（设计决策记录）。

**当前状态：实现完成，四道门禁全绿，等待集成。**
