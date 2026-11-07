# yuv · 公开 API（API.md）

> 与 `pkg.generated.mbti` 一致。全部函数为 `declare`（**无实现**，预期 `0068` 告警）。
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
| `Channels` | `pub type` | `Int` 别名 |
| `FrameConverter` | `pub trait` | `to_rgb` 契约 |

## 函数签名

| 签名 | 参数与所有权 | 返回 / 错误 | 资源与线程约束 | TODO |
|---|---|---|---|---|
| `to_rgb(frame : YuvFrame, config : ConvertConfig) -> RgbImage raise YuvError` | 均为只读纯值；不缓存、不转移 | 新分配 `RgbImage` / `YuvError` | 纯函数可并发；无句柄 | 系数表、三平面 stride 读取、SIMD 快路径、bench 阈值 |
| `rotate(img : RgbImage, deg : Rotation) -> RgbImage raise YuvError` | `img` 只读 | 新值 / `UnsupportedRotation` | 纯函数 | 90/180/270 索引映射 |
| `mirror_x(img : RgbImage) -> RgbImage raise YuvError` | `img` 只读 | 新值 | 纯函数 | 逐行反转 |
| `RgbImage::channels(self) -> Channels` | `self` 只读 | 每像素通道数（供组合根适配） | 无状态 | — |
| `RgbImage::bytes(self) -> Bytes` | `self` 只读 | 底层字节（只读引用语义，不复制） | 无状态 | — |

## 错误构造速查

`InvalidDimensions(w, h)` · `PlaneCountMismatch(expected, actual)` · `PlaneTooSmall(index, size)` · `UnsupportedFormat` · `UnsupportedRotation` · `StrideMismatch` · `BufferSizeMismatch(expected, actual)`

## Wire 契约提示

`yuv::YuvFrame` 与 `camera2::YuvFrame`、`yuv::RgbImage` 与 `pose::RgbImage` **结构同构但类型不同**（MoonBit 名义类型）。组合根负责构造目标类型，`Bytes` 为引用计数，浅拷贝成本低。见 `../docs/architecture.md` §4。

## 非目标

相机取帧、编解码、推理、渲染、GPU/SIMD 调度、HDR 色彩管理。

## 状态

`moon check`：✅ 0 error，5 × `0068`。API 快照：`pkg.generated.mbti`。实现：❌ 后续轮。
