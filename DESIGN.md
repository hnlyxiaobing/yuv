# yuv · 设计契约（DESIGN.md）

> 初稿 2026-11-06 ｜ **API 冻结前对账 / 2026-11-07** ｜ 状态：**已实现**（像素转换 / 旋转 / 镜像），无 I/O、四道门禁全绿（冻结后签名变更即破坏性变更）

## 1. 分层位置与职责

L3 感知绑定层的**纯计算叶子库**，也是 Frame/Rgb Wire 的一端。职责：YUV 帧值 → RGB 图像值，外加旋转与镜像。无 I/O、无 FFI、无状态。

## 2. 模块边界 / 依赖方向 / 数据流

```
camera2::YuvFrame  ──(组合根按 Wire 构造)──►  yuv::YuvFrame
                                              │ to_rgb
                                              ▼
                                        yuv::RgbImage ──(组合根按 Wire 构造)──► pose::RgbImage
```

零跨模块 import（见 `DECISIONS.md` §2）。`yuv` 不知道相机与推理的存在；`camera2` / `pose` 各自定义同构值类型，由组合根适配。`pose` **不依赖** `yuv` 的实现，避免类型复用环（双方都想复用对方的值类型定义而形成循环依赖）。

## 3. 核心数据结构

| 类型 | 作用 |
|---|---|
| `YuvFrame { width, height, format, planes, timestamp_ns }` | 中性帧值类型 |
| `PlaneDescriptor { data, row_stride, pixel_stride }` | 平面描述，保留非紧凑布局 |
| `RgbImage { width, height, layout, data, timestamp_ns }` | 中性 RGB 值类型 |
| `YuvFormat` / `RgbLayout` / `ColorMatrix` / `Rotation` | 格式、通道顺序、色彩系数、旋转角全部显式枚举 |
| `ConvertConfig { matrix, layout, rotation, mirror_x, clamp }` | 转换配置 |
| `YuvError` | 7 个可判定输入错误 |
| `Channels` | `Int32` 别名（`pub type Channels = Int32`） |
| `FrameConverter` trait | `to_rgb` 纯计算契约（**契约 trait，当前无 `impl`**；自由函数 `to_rgb` 为实现入口，签名一致） |

## 4. 错误模型

`YuvError`：`InvalidDimensions(Int32, Int32)`、`PlaneCountMismatch(Int32, Int32)`、`PlaneTooSmall(Int32, Int32)`、`UnsupportedFormat(String)`、`UnsupportedRotation(String)`、`StrideMismatch(String)`、`BufferSizeMismatch(Int32, Int32)`（与快照逐字一致，共 7 个构造）。`UnsupportedFormat` / `UnsupportedRotation` 因 `YuvFormat` / `Rotation` 为封闭枚举而当前不可达，保留给未来开放取值。

全部 `raise YuvError`；**禁止越界读取与 panic**；错误只在本模块内，组合根负责映射。

## 5. 资源生命周期

全部纯值。`to_rgb` / `rotate` / `mirror_x` 返回**新分配**的 `RgbImage`，不修改输入、不缓存输入引用；无需释放函数。

## 6. 线程 / 并发边界

纯函数、无可变全局状态、无静态查表缓存；可并发调用。色彩系数由 `coeffs_for` 从字面常量按 `ColorMatrix` 现场计算，不使用 `lazy` 或可变全局。

## 7. 平台约束与外部依赖

- `preferred_target = "wasm"`（未改动），全后端。
- 外部依赖：无。事实约束：Camera2 NDK `AIMAGE_FORMAT_YUV_420_888` 三平面恒为 Y/U/V，Y 平面 pixelStride=1，U/V 共享 rowStride 与 pixelStride。
- 优化路径：SIMD 为后续可选，不改变公开签名。

## 8. 输入输出类型与错误传播（纯 MoonBit 库）

| 输入 | 输出 | 错误传播 |
|---|---|---|
| `YuvFrame + ConvertConfig` | `RgbImage` | `YuvError`（尺寸/平面/stride/缓冲） |
| `RgbImage + Rotation` | `RgbImage` | `InvalidDimensions` / `BufferSizeMismatch`（`UnsupportedRotation` 当前不可达） |
| `RgbImage` | `RgbImage`（镜像） | `InvalidDimensions` / `BufferSizeMismatch` |
| `RgbImage` | `Channels` / `Bytes` | 无（只读） |

3 个自由函数（`to_rgb` / `rotate` / `mirror_x`）与 `RgbImage::{channels, bytes}` 两个方法均为 `pub fn` **真实实现**（无 `declare` 占位、无 `0068` 告警）；具体值类型用真实定义（见 `DECISIONS.md` §4）。

## 9. 可替换性与实现细节不泄漏

上层只看到中性帧/图像值类型；看不到像素循环、系数表、SIMD 分支。换相机来源、换推理后端、甚至换成 GPU 转换，都不影响 `pose` 的 API。

## 10. 测试策略

| 层次 | 内容 |
|---|---|
| 黑盒 | 固定像素 golden：NV21、NV12、I420、YUV_420_888（含 stride ≠ width 的样本）；四种 ColorMatrix；四种 Rotation；镜像 |
| 白盒 | 平面越界、stride 校验、clamp 边界 |
| 基准 | `moon bench`：720p / 1080p 单帧耗时固定阈值，防止回退（**本轮未引入 bench**，属后续优化门禁） |
| 门禁 | 四道门禁：`moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check`（2026-11-07 实跑全绿，35 tests） |

## 11. 验收标准（2026-11-07 复核）

1. 与参考实现逐像素一致（golden 覆盖 NV21 / NV12 / I420 / YUV_420_888 与四种 `ColorMatrix`）；2. 所有非法输入返回 `YuvError` 而非越界读取（✅）；3. `moon bench` 不回退（⬜ bench 未引入，后移）；4. `moon check --deny-warn` 转绿（✅ 2026-11-07 实跑）。

## 12. 未解决问题 / 待验证假设

- 参照包 `PaiGack/heic@0.1.0` 转换内核的可移植性未实测（`[待验证假设]`，见 `DECISIONS.md` §1）。
- SIMD 快路径在 wasm / native 两目标的一致性与收益未验证。
- BT.601 全幅度 vs 有限幅度的目标设备实际约定需真机确认。
- `moon bench` 阈值门禁尚未引入（无 bench 资产）。

## 13. 当前状态

`yuv.mbt` / `convert.mbt` 的全部类型与 3 个自由函数（`to_rgb` / `rotate` / `mirror_x`）+ `RgbImage::{channels, bytes}` 均为**真实实现**，公开 API 带 `///` 文档注释；`pkg.generated.mbti` 快照与源码一致。**无 I/O、无 FFI、无外部依赖**（非目标不变）。四道门禁全绿（35 tests，2026-11-07 实跑）。

## References

`DECISIONS.md`（设计决策记录：Wire Contract 与值类型定义策略、依赖五门槛）· `https://developer.android.google.cn/ndk/reference/group/media`（YUV_420_888）
