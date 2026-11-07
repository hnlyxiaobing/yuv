# yuv · 设计契约（DESIGN.md）

> Round-1 / 2026-11-06 ｜ 状态：架构与声明可评审，无业务逻辑

## 1. 分层位置与职责

L3 感知绑定层的**纯计算叶子库**，也是 Frame/Rgb Wire 的一端。职责：YUV 帧值 → RGB 图像值，外加旋转与镜像。无 I/O、无 FFI、无状态。

## 2. 模块边界 / 依赖方向 / 数据流

```
camera2::YuvFrame  ──(组合根按 Wire 构造)──►  yuv::YuvFrame
                                              │ to_rgb
                                              ▼
                                        yuv::RgbImage ──(组合根按 Wire 构造)──► pose::RgbImage
```

零跨模块 import（ADR-0002）。`yuv` 不知道相机与推理的存在；`camera2` / `pose` 各自定义同构值类型，由组合根适配。`pose` **不依赖** `yuv` 的实现，避免 K6 环。

## 3. 核心数据结构

| 类型 | 作用 |
|---|---|
| `YuvFrame { width, height, format, planes, timestamp_ns }` | 中性帧值类型 |
| `PlaneDescriptor { data, row_stride, pixel_stride }` | 平面描述，保留非紧凑布局 |
| `RgbImage { width, height, layout, data, timestamp_ns }` | 中性 RGB 值类型 |
| `YuvFormat` / `RgbLayout` / `ColorMatrix` / `Rotation` | 格式、通道顺序、色彩系数、旋转角全部显式枚举 |
| `ConvertConfig { matrix, layout, rotation, mirror_x, clamp }` | 转换配置 |
| `YuvError` | 7 个可判定输入错误 |
| `Channels` | `Int` 别名 |
| `FrameConverter` trait | `to_rgb` 纯计算契约 |

## 4. 错误模型

`YuvError`：`InvalidDimensions(Int, Int)`、`PlaneCountMismatch(Int, Int)`、`PlaneTooSmall(Int, Int)`、`UnsupportedFormat(String)`、`UnsupportedRotation(String)`、`StrideMismatch(String)`、`BufferSizeMismatch(Int, Int)`。

全部 `raise YuvError`；**禁止越界读取与 panic**；错误只在本模块内，组合根负责映射。

## 5. 资源生命周期

全部纯值。`to_rgb` / `rotate` / `mirror_x` 返回**新分配**的 `RgbImage`，不修改输入、不缓存输入引用；无需释放函数。

## 6. 线程 / 并发边界

纯函数、无可变全局状态、无静态查表缓存（若实现轮引入系数表，须为不可变常量）；可并发调用。

## 7. 平台约束与外部依赖

- `preferred_target = "wasm"`（未改动），全后端。
- 外部依赖：无。事实约束：Camera2 NDK `AIMAGE_FORMAT_YUV_420_888` 三平面恒为 Y/U/V，Y 平面 pixelStride=1，U/V 共享 rowStride 与 pixelStride。
- 优化路径：SIMD 为后续可选，不改变公开签名。

## 8. 输入输出类型与错误传播（纯 MoonBit 库）

| 输入 | 输出 | 错误传播 |
|---|---|---|
| `YuvFrame + ConvertConfig` | `RgbImage` | `YuvError`（尺寸/平面/stride/缓冲） |
| `RgbImage + Rotation` | `RgbImage` | `UnsupportedRotation` |
| `RgbImage` | `RgbImage`（镜像） | 无 |
| `RgbImage` | `Channels` / `Bytes` | 无（只读） |

`declare` 只用于函数签名；具体值类型用真实定义（ADR-0001）。

## 9. 可替换性与实现细节不泄漏

上层只看到中性帧/图像值类型；看不到像素循环、系数表、SIMD 分支。换相机来源、换推理后端、甚至换成 GPU 转换，都不影响 `pose` 的 API。

## 10. 测试策略

| 层次 | 内容 |
|---|---|
| 黑盒 | 固定像素 golden：NV21、NV12、I420、YUV_420_888（含 stride ≠ width 的样本）；四种 ColorMatrix；四种 Rotation；镜像 |
| 白盒 | 平面越界、stride 校验、clamp 边界 |
| 基准 | `moon bench`：720p / 1080p 单帧耗时固定阈值，防止回退 |
| 门禁 | `moon fmt --check` / `moon check` / `moon test --enable-coverage` / `moon info` |

## 11. 验收标准（实现轮）

1. 与参考实现逐像素一致；2. 所有非法输入返回 `YuvError`；3. `moon bench` 不回退；4. R4 `--deny-warn` 转绿。

## 12. 未解决问题 / 待验证假设

- `heic@0.1.0` 转换内核的可移植性未实测（`[待验证假设]`）。
- SIMD 快路径在 wasm / native 两目标的一致性与收益未验证。
- BT.601 全幅度 vs 有限幅度的目标设备实际约定需真机确认。

## 13. 当前状态与 TODO

`yuv.mbt` 已写入全部类型与 5 个 `declare` 函数，公开 API 有 `///` 文档注释与 `TODO(实现轮)`。**未实现任何像素计算逻辑**。

## References

`../docs/architecture.md` §4 · `../docs/adr/ADR-0002`、`ADR-0004` · `https://developer.android.google.cn/ndk/reference/group/media`（YUV_420_888）
