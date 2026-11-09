# yuv · 公开 API（API.md）

> **API 冻结前对账已完成（2026-11-07）**：本文已与 `pkg.generated.mbti` 快照及源码公开签名逐项对账一致；**冻结后签名变更即破坏性变更**。
> 3 个自由函数与 2 个方法均为**真实实现**（`pub fn`，非 `declare` 占位，0 条 `0068`）。
> 错误传播统一 `raise YuvError`；无外部句柄；所有转换返回新值、不修改输入。

## 类型

| 类型 | 种类 | 说明 |
|---|---|---|
| `YuvFrame` | `pub(all) struct` | width / height / `format` / `planes` / timestamp_ns |
| `PlaneDescriptor` | `pub(all) struct` | `data : Bytes` + `row_stride` + `pixel_stride` |
| `RgbImage` | `pub(all) struct` | width / height / `layout` / `data : Bytes` / timestamp_ns |
| `YuvFormat` | `pub(all) enum` | Nv21 / Nv12 / Yuv420888 / I420 |
| `RgbLayout` | `pub(all) enum` | Rgb / Bgr / Rgba / Bgra |
| `ColorMatrix` | `pub(all) enum` | Bt601Limited / Bt601Full / Bt709Limited / Bt709Full |
| `Rotation` | `pub(all) enum` | D0 / D90 / D180 / D270 |
| `ConvertConfig` | `pub(all) struct` | matrix / layout / rotation / mirror_x / clamp |
| `YuvError` | `pub suberror` | 7 个输入错误 |
| `Channels` | `pub type` | `Int32` 别名（快照：`pub type Channels = Int32`） |
| `FrameConverter` | `pub trait` | `fn to_rgb(Self, ConvertConfig) -> RgbImage raise YuvError`；**契约 trait，当前无 `impl`**（自由函数 `to_rgb` 是实现入口，签名与 trait 方法一致） |

## 函数签名

| 签名 | 参数与所有权 | 返回 / 错误 | 资源与线程约束 | 实现要点 / 备注 |
|---|---|---|---|---|
| `to_rgb(frame : YuvFrame, config : ConvertConfig) -> RgbImage raise YuvError` | 均为只读纯值；不缓存、不转移 | 新分配 `RgbImage` / `YuvError` | 纯函数可并发；无句柄 | **已实现**：BT.601 / BT.709 有限/全幅度系数表（不可变常量）、按 `row_stride` / `pixel_stride` 读取非紧凑平面、clamp 边界处理；SIMD 快路径与 `moon bench` 阈值门禁为后续优化（不改公开签名） |
| `rotate(img : RgbImage, deg : Rotation) -> RgbImage raise YuvError` | `img` 只读 | 新值 / `InvalidDimensions`、`BufferSizeMismatch` | 纯函数 | **已实现**：90/180/270 像素索引映射；`D0` 返回内容一致的新值；`UnsupportedRotation` 保留给未来开放取值，**当前不可达**（枚举封闭） |
| `mirror_x(img : RgbImage) -> RgbImage raise YuvError` | `img` 只读 | 新值 / `InvalidDimensions`、`BufferSizeMismatch` | 纯函数 | **已实现**：逐行反转 |
| `RgbImage::channels(self) -> Int32` | `self` 只读 | 每像素通道数（返回 `Channels`，即 `Int32` 别名；供组合根适配） | 无状态 | — |
| `RgbImage::bytes(self) -> Bytes` | `self` 只读 | 底层字节（只读引用语义，不复制） | 无状态 | — |

## 错误构造速查

`InvalidDimensions(w, h)` · `PlaneCountMismatch(expected, actual)` · `PlaneTooSmall(index, size)` · `UnsupportedFormat(fmt)` · `UnsupportedRotation(deg)` · `StrideMismatch(detail)` · `BufferSizeMismatch(expected, actual)`（`UnsupportedFormat` / `UnsupportedRotation` / `StrideMismatch` 的参数为 `String`，其余为 `Int32`，与快照一致；前两者因 `YuvFormat` / `Rotation` 是封闭枚举而**当前不可达**，保留给未来开放取值）

## Wire 契约提示

`yuv::YuvFrame` 与 `camera2::YuvFrame`、`yuv::RgbImage` 与 `pose::RgbImage` **结构同构但类型不同**（MoonBit 名义类型），各自定义、由组合根适配。组合根负责构造目标类型，`Bytes` 为引用计数，浅拷贝成本低。Wire 契约详见 `DESIGN.md` §2、`DECISIONS.md` §2。

## 非目标

相机取帧、编解码、推理、渲染、GPU/SIMD 调度、HDR 色彩管理。

## 状态

**API 冻结前对账已完成**：API.md ↔ `pkg.generated.mbti` ↔ 源码公开签名三方一致；**冻结后签名变更即破坏性变更**。
四道门禁实跑全绿（2026-11-07）：`moon check --deny-warn`（0 error / 0 warn）· `moon build` · `moon test`（**35 tests** 全过）· `moon fmt --check`。
API 快照：`pkg.generated.mbti`（只读，未改动）。实现：✅ `to_rgb` / `rotate` / `mirror_x` / `RgbImage::{channels, bytes}` 均为真实实现；SIMD 快路径与 `moon bench` 阈值为后续优化（不改公开签名）。
