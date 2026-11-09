# hnlyxiaobing/yuv

**YUV 转换基础库 —— NV21 / YUV_420_888 转 RGB、旋转与镜像，纯计算、无平台依赖。**

> 状态：**实现完成，API 冻结前对账已完成（2026-11-07）**。数据结构与 5 个 API（`to_rgb` / `rotate` / `mirror_x` / `RgbImage::{channels, bytes}`）全部为真实实现（0 条 `0068`），四道门禁 `moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check` 全绿（35 tests；`pkg.generated.mbti` 与源码对账一致，冻结后签名变更即破坏性变更）。**纯计算、无 I/O、无平台依赖**。

## 定位与为什么存在

生态检索结论（mooncakes registry，2026-11-06）：没有独立的 NV21 / YUV 转换库，但存在 `PaiGack/heic@0.1.0`（内嵌 YUV420→RGBA8 转换内核）与 `lkdrt/palette_forge@0.1.0`（YUV 色彩空间处理）。因此选型判定为**移植既有转换内核 + 纯 MoonBit 自研 stride/色彩空间封装**，比"完全从零自研"少写色彩系数表，同时不引入 HEIC 编解码这类无关大依赖。两参照包为 mooncakes registry **自述许可**、许可证原文**未逐文件核验**，抽取范围仅限色彩转换系数与算法思路（详见 `DECISIONS.md` §1）。

Android 相机输出 YUV，推理与渲染吃 RGB，缺这一环体感闭环就断在取帧之后。本库是**叶子库**：相机、推理、渲染三方共用其值类型，但本库不依赖任何一方。

## 能力范围 / 非目标

- **做**：NV21 / NV12 / YUV_420_888 / I420 → RGB/BGR/RGBA/BGRA；按 `row_stride` / `pixel_stride` 读取非紧凑平面；BT.601 / BT.709 有限/全幅度系数**显式传参**；90/180/270 旋转；水平镜像；输出通道数与字节访问。
- **不做**：相机取帧、视频编码/解码、推理、渲染、GPU/SIMD 调度（预留优化路径）、HDR / 色彩管理。

## 公开接口（速览）

`to_rgb(YuvFrame, ConvertConfig) -> RgbImage raise YuvError`、`rotate`、`mirror_x`、`RgbImage::{channels, bytes}`。完整签名见 `API.md`。

## 依赖

- **本轮零依赖**；独立 `moon.mod`，`moon check` 独立通过。
- 后续：可继续参照 `PaiGack/heic@0.1.0` 的转换内核（不引入 HEIC 依赖）；可选 `mizchi/simd@0.6.1` 作 SIMD 快路径评估，但按 `DECISIONS.md` §5 的依赖五门槛须先说明用途与维护风险。

## 平台与许可风险

- 平台：全后端（`preferred_target = "wasm"`，未改动）；桌面即可测试，是本轮**成本最低、可测试性最高**的库。
- 许可：本仓库 Apache-2.0；转换算法为公开标准系数，无外部二进制、无再分发风险。
- 风险：色彩空间系数必须显式（避免隐式 BT.601 假设）；YUV_420_888 三平面 U/V 共享 `rowStride`/`pixelStride`、Y 平面 pixelStride=1，不能假设紧凑布局（**已按 stride 校验实现**）；大图逐像素性能计划用 `moon bench` 固定阈值守门（**本轮未引入 bench**，属后续优化）。

## 测试与验收

- **测试策略**：固定像素 golden（含 NV21 与 stride 非紧凑的 YUV_420_888 样本）；BT.601/709 系数差分；尺寸/平面/stride/缓冲非法输入；`moon bench` 阈值（**后移，本轮未引入**）。
- **验收标准**：输出与参考实现逐像素一致（golden 覆盖）；所有非法输入返回 `YuvError` 而非越界读取（✅）；`moon check --deny-warn` 转绿（✅ 2026-11-07 实跑）。
- **门禁实跑（2026-11-07）**：`moon clean` → `moon check --deny-warn` → `moon build` → `moon test`（**35 tests** 全过）→ `moon fmt --check`，全部 exit 0。

## 当前状态 / 本轮产物

| 项 | 状态 |
|---|---|
| `yuv.mbt` / `convert.mbt`：数据结构 + 5 个 API（真实实现）+ 文档注释 | ✅ |
| `pkg.generated.mbti` API 快照（与源码对账一致） | ✅ |
| 像素计算 / 旋转 / 镜像 | ✅ 已实现 |
| SIMD 快路径 / `moon bench` 阈值门禁 | ⬜ 后续优化（不改公开签名） |
| 四道门禁：`moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check` | ✅ 全绿（35 tests） |

## 选型与优先理由

选型排序判据复核（2026-11-06）：本库**无许可风险、纯函数可测（golden 逐像素测试即可覆盖）、有可移植内核参照**，三项判据全优，因此作为首批实现项之一；同时它是「取帧 → 转换 → 推理」感知链路的像素环节起点。

## 文档索引

`DESIGN.md`（设计契约，含 Wire Contract）· `API.md`（公开 API）· `DECISIONS.md`（设计决策记录：选型、值类型与组合根、显式色彩矩阵与 stride、真实实现、依赖五门槛）
