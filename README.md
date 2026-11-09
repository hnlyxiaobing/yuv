# hnlyxiaobing/yuv

**YUV 转换基础库 —— NV21 / YUV_420_888 转 RGB、旋转与镜像，纯计算、无平台依赖。**

> 状态：**实现完成 + R4 性能轮（2026-11-09）**。数据结构与 6 个 API（`to_rgb` / `to_rgb_fast` / `rotate` / `mirror_x` / `RgbImage::{channels, bytes}`）全部为真实实现（0 条 `0068`），四道门禁 `moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check` 全绿（**47 tests**；`pkg.generated.mbti` 与源码对账一致，冻结后签名变更即破坏性变更）。`moon bench` 6 项基准 + fail-closed 阈值门禁实测通过（见下）。**纯计算、无 I/O、无平台依赖**。

## 定位与为什么存在

生态检索结论（mooncakes registry，2026-11-06）：没有独立的 NV21 / YUV 转换库，但存在 `PaiGack/heic@0.1.0`（内嵌 YUV420→RGBA8 转换内核）与 `lkdrt/palette_forge@0.1.0`（YUV 色彩空间处理）。因此选型判定为**移植既有转换内核 + 纯 MoonBit 自研 stride/色彩空间封装**，比"完全从零自研"少写色彩系数表，同时不引入 HEIC 编解码这类无关大依赖。两参照包为 mooncakes registry **自述许可**、许可证原文**未逐文件核验**，抽取范围仅限色彩转换系数与算法思路（详见 `docs/DECISIONS.md` §1）。

Android 相机输出 YUV，推理与渲染吃 RGB，缺这一环体感闭环就断在取帧之后。本库是**叶子库**：相机、推理、渲染三方共用其值类型，但本库不依赖任何一方。

## 能力范围 / 非目标

- **做**：NV21 / NV12 / YUV_420_888 / I420 → RGB/BGR/RGBA/BGRA；按 `row_stride` / `pixel_stride` 读取非紧凑平面；BT.601 / BT.709 有限/全幅度系数**显式传参**；90/180/270 旋转；水平镜像；输出通道数与字节访问。
- **不做**：相机取帧、视频编码/解码、推理、渲染、GPU/SIMD 调度（预留优化路径）、HDR / 色彩管理。

## 公开接口（速览）

`to_rgb(YuvFrame, ConvertConfig) -> RgbImage raise YuvError`、`rotate`、`mirror_x`、`RgbImage::{channels, bytes}`。完整签名见 `docs/API.md`。

## 依赖

- **本轮零依赖**；独立 `moon.mod`，`moon check` 独立通过。
- 后续：可继续参照 `PaiGack/heic@0.1.0` 的转换内核（不引入 HEIC 依赖）；可选 `mizchi/simd@0.6.1` 作 SIMD 快路径评估，但按 `docs/DECISIONS.md` §5 的依赖五门槛须先说明用途与维护风险。

## 平台与许可风险

- 平台：全后端（`preferred_target = "wasm"`，未改动）；桌面即可测试，是本轮**成本最低、可测试性最高**的库。
- 许可：本仓库 Apache-2.0；转换算法为公开标准系数，无外部二进制、无再分发风险。
- 风险：色彩空间系数必须显式（避免隐式 BT.601 假设）；YUV_420_888 三平面 U/V 共享 `rowStride`/`pixelStride`、Y 平面 pixelStride=1，不能假设紧凑布局（**已按 stride 校验实现**）；大图逐像素性能由 `moon bench` + `tools/bench-gate.ps1` 固定阈值守门（**已落地，fail-closed**）。

## 性能（R4，2026-11-09 实测）

参考路径 `to_rgb` 与定点快路径 `to_rgb_fast`（Q16.16 系数表 + 2×2 批量展开内核，输出逐字节等价）：

| 基准（640×480） | 均值 (ms) |
|---|---|
| `to_rgb nv21` / `to_rgb_fast nv21` | 22.75 / **8.68** |
| `to_rgb i420` / `to_rgb_fast i420` | 26.60 / **9.28** |
| `rotate d90` / `mirror_x` | 2.58 / 2.62 |

阈值门禁：`powershell -File tools/bench-gate.ps1`（绝对阈值含 ~3x 余量 + 「快路径不得慢于参考路径」相对硬门禁；缺基准/解析失败一律 fail-closed，退出码 0/1）。

## 测试与验收

- **测试策略**：固定像素 golden（含 NV21 与 stride 非紧凑的 YUV_420_888 样本）；BT.601/709 系数差分；尺寸/平面/stride/缓冲非法输入；快慢路径逐字节等价断言；`moon bench` 阈值门禁（**已落地**）。
- **验收标准**：输出与参考实现逐像素一致（golden 覆盖）；所有非法输入返回 `YuvError` 而非越界读取（✅）；`moon check --deny-warn` 转绿（✅ 2026-11-09 实跑）。
- **门禁实跑（2026-11-09）**：`moon clean` → `moon check --deny-warn` → `moon build` → `moon test`（**47 tests** 全过）→ `moon fmt --check` → 第 5 道快照门禁（`moon info` 后 `pkg.generated.mbti` 无 diff）→ `tools/bench-gate.ps1`（PASSED），全部 exit 0。

## 当前状态 / 本轮产物

| 项 | 状态 |
|---|---|
| `yuv.mbt` / `convert.mbt` / `fast.mbt`：数据结构 + 6 个 API（真实实现）+ 文档注释 | ✅ |
| `pkg.generated.mbti` API 快照（与源码对账一致） | ✅ |
| 像素计算 / 旋转 / 镜像 | ✅ 已实现 |
| 定点快路径 `to_rgb_fast`（Q16.16 + 2×2 批量）/ 等价性测试 | ✅ 已实现（加法性 API） |
| `moon bench` 6 基准 + fail-closed 阈值门禁（`tools/bench-gate.ps1`） | ✅ 已落地，实测 PASSED |
| 四道门禁：`moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check` | ✅ 全绿（47 tests） |

## 选型与优先理由

选型排序判据复核（2026-11-06）：本库**无许可风险、纯函数可测（golden 逐像素测试即可覆盖）、有可移植内核参照**，三项判据全优，因此作为首批实现项之一；同时它是「取帧 → 转换 → 推理」感知链路的像素环节起点。

## 文档索引

`docs/DESIGN.md`（设计契约，含 Wire Contract）· `docs/API.md`（公开 API）· `docs/DECISIONS.md`（设计决策记录：选型、值类型与组合根、显式色彩矩阵与 stride、真实实现、依赖五门槛）
