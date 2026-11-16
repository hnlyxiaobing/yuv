# yuv · YUV↔RGB 转换

> 独立发布单元 ｜ L3 感知绑定 ｜ `preferred_target = wasm` ｜ Apache-2.0
> 状态：`moon test` **48/48** 通过（2026-11-11 本机实测）；本文件是本仓库**唯一**说明文档。
> 公开 API 以 `pkg.generated.mbti` 为准（由 `moon info` 生成，禁手工编辑）；加法性变更须登记簿记 + 快照审阅 + 快照门禁。

## 1. 定位与边界

纯计算地把四种 YUV 布局转成 RGB，并提供旋转、镜像与定点快路径。

**能力**

- NV21 / NV12 / I420 / YV12 → RGB 与四种布局；显式 stride / 色彩矩阵，无隐式假设
- `to_rgb`（逐通道误差 ≤1 LSB）与 `to_rgb_fast`（Q16.16 定点）
- `rotate` / `mirror_x` 与 `RgbImage::{channels,bytes}`
- `tools/bench-gate.ps1` 阈值门禁已落地并 PASSED（nv21 22.75→8.68 ms、i420 26.60→9.28 ms）

**非目标**

- 不做编解码、不做缩放与色彩增强，不感知相机或模型
- 不引入 SIMD 快路径或第三方色彩库

## 2. 关键设计决策（本仓库自足记录）

- 唯一「移植 + 自研」项目：仅抽取 `PaiGack/heic@0.1.0` / `lkdrt/palette_forge@0.1.0` 的公开标准系数，不纳入任何第三方代码。
- 所有参数（色彩矩阵、stride、pixel_stride）显式传入；NV21/NV12 色度 `pixel_stride` 强制等于 2。
- `to_rgb_fast` 与 bench 阈值门禁均为 R4 后加法性落地，早期「bench 未引入」的表述已作废。

## 3. 公开 API 索引（自动抽取 `pkg.generated.mbti` 的 `pub` 声明行；完整字段见快照）

```text
pub fn mirror_x(RgbImage) -> RgbImage raise YuvError
pub fn rotate(RgbImage, Rotation) -> RgbImage raise YuvError
pub fn to_rgb(YuvFrame, ConvertConfig) -> RgbImage raise YuvError
pub fn to_rgb_fast(YuvFrame, ConvertConfig) -> RgbImage raise YuvError
pub(all) enum ColorMatrix {
pub(all) struct ConvertConfig {
pub(all) struct PlaneDescriptor {
pub(all) struct RgbImage {
pub fn RgbImage::bytes(Self) -> Bytes
pub fn RgbImage::channels(Self) -> Int32
pub(all) enum RgbLayout {
pub(all) enum Rotation {
pub(all) enum YuvFormat {
pub(all) struct YuvFrame {
```

## 4. 依赖、平台与许可

零第三方依赖（仅 core/bench，仅测试用）；`preferred_target = wasm`；Apache-2.0。

## 5. 命令行与验证

- 本库无 CLI；`cmd/main` 为模板。
- 复验：`moon clean` → `moon check --deny-warn` → `moon build` → `moon test` → `moon fmt --check` → `moon info` 后检查 `pkg.generated.mbti` 无意外 diff。
- 本仓库为独立 Git 仓库，文档与 CI 均自包含，不依赖工作区其他目录。

## 6. 风险与未决

- 两个参照包的许可原文未逐文件核验，核验前不进入分发产物。
- SIMD 快路径仍属后续可选优化，未排期。

