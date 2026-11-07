# hnlyxiaobing/yuv

> Round-1 · 架构与声明可评审（2026-11-06）。本包只有中性帧/图像值类型、转换配置与 `declare` 函数签名，**无像素计算逻辑**。`moon check`：0 error，5 × `[0068]`（预期）。

纯计算叶子库：YUV → RGB、旋转、镜像；Frame/Rgb Wire 契约的一端。

完整文档见同目录 `README.md`、`DESIGN.md`、`API.md`；总体架构与决策见 `../docs/architecture.md`、`../docs/adr/`。

**当前状态：等待评审，不进入实现。**
