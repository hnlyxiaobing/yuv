# yuv · 设计决策记录（DECISIONS.md）

> 本文记录 `yuv` 的关键设计决策（背景 → 决策 → 理由 → 后果），内容**源自开发期决策记录**（原文档属于作者本地开发工作区的管理材料，不随本仓库发布），已改写为完全自足的表述。社区开发者仅凭本仓库即可理解全部设计动机，无需任何仓库外文件。
>
> 相关文档：`README.md`（总览）· `DESIGN.md`（设计契约）· `API.md`（公开 API）。

## 1. 选型：移植转换内核 + 纯 MoonBit 自研封装

### 背景

本库需要提供 YUV → RGB 像素转换（NV21 / NV12 / YUV_420_888 / I420 → RGB/BGR/RGBA/BGRA）。开发期对 mooncakes registry 做过一轮生态检索（2026-11-06），结论：

- **不存在**独立的 NV21 / YUV 转换库；
- `PaiGack/heic@0.1.0` 内嵌 YUV420→RGBA8 转换内核；
- `lkdrt/palette_forge@0.1.0` 含 YUV 色彩空间处理。

### 决策

判定为**移植 + 纯 MoonBit 自研**：

- 转换系数与转换内核的算法思路**参照** `PaiGack/heic@0.1.0` 与 `lkdrt/palette_forge@0.1.0` 抽取改写，抽取范围**仅限**色彩转换系数与算法思路；
- stride 处理、色彩空间封装、旋转 / 镜像与全部工程化（输入校验、错误模型、测试）为**纯 MoonBit 自研**；
- **不引入** HEIC 编解码依赖——HEIC 编解码是与本库无关的大依赖，会把依赖面扩大到图像容器解析一整层。

**许可状态（如实注明）**：上述两个参照包的许可为 **mooncakes registry 自述许可**（registry 元数据自述 SPDX），**许可证原文未逐文件核验，其具体许可证条款待确认**。因此抽取严格限于「公开标准色彩系数 + 算法思路」，不逐文件复制其代码。BT.601 / BT.709 色彩系数本身是公开国际标准，无许可问题。本仓库自身 Apache-2.0，零外部依赖、无外部二进制、无再分发风险。

### 理由

- 比"完全从零自研"少写色彩系数表，缩短实现路径；
- 不引入 HEIC 编解码这类无关大依赖，依赖面收敛为零；
- 本库纯计算、无 I/O、无平台依赖，是成本最低、可测试性最高的环节（固定像素 golden 逐像素测试即可覆盖）。

### 后果

- **正面**：35/35 测试全绿；零依赖、`moon check` 独立通过；转换算法为公开标准系数，无外部二进制、无再分发风险。
- **负面 / 待验证**：参照包转换内核的**可移植性未实测**（待验证假设）；两参照包许可证原文未逐文件核验——若未来想直接复制其代码（而非仅参照算法思路），须先逐文件核验许可。

## 2. 零跨模块 import：同构值类型各自定义 + 组合根适配

### 背景

MoonBit 是名义类型系统：两个模块里结构完全相同的 `struct` 也不是同一类型。本库处在「取帧（camera2）→ 像素转换（yuv）→ 姿态推理（pose）」链路中间；若消费方直接 import 本库的类型定义（或本库反向 import 消费方），`yuv` 与 `camera2` / `pose` 之间会形成循环的**类型复用环**——双方都想复用对方的帧 / 图像类型定义，编译期即成为不可解的双向依赖。

### 决策

- **零跨模块 import**：本库不 import 任何其他模块，也不要求任何模块 import 本库；独立 `moon.mod`，`moon check` 独立通过。
- **Wire Contract（帧数据契约）**：跨模块传递的帧 / 图像一律是 `{ width, height, format, Bytes, timestamp }` 形状的**纯值**。`yuv::YuvFrame` 与 `camera2::YuvFrame`、`yuv::RgbImage` 与 `pose::RgbImage` **结构同构但类型不同**（名义类型），各模块**各自定义**自己的同构值类型，不共享类型定义。
- **组合根适配**：由应用侧的组合根（composition root，不是库）用 Wire 值在各库同名值类型间做轻量适配（`Bytes` 为引用计数，浅拷贝成本低）；`pose` **不依赖** `yuv` 的实现，`yuv` 也不知道相机与推理的存在。
- 抽象（trait）放在消费方，实现方不反向依赖（如 `FrameConverter` 只是纯计算契约）。

### 理由

- 彻底消解与 `camera2` / `pose` 的类型复用环，无循环依赖；
- 各模块可完全并行开发、独立 `moon check`；
- API 边界被迫写成中性值类型：换相机来源、换推理后端、甚至换成 GPU 转换都不影响本库 API。

### 后果

- **正面**：零依赖、无环、纯值可并发；可替换性与"实现细节不泄漏"由类型边界保证。
- **负面**：同构值类型在多个模块各定义一次，存在**结构漂移风险**——由 `pkg.generated.mbti` API 快照对账与组合根测试守住；组合根需写少量显式适配代码。

## 3. 色彩矩阵与 stride 全显式

### 背景

两类隐式假设是 YUV 转换最常见的错误来源：

1. **色彩矩阵隐式化**：不同色彩空间（BT.601 / BT.709）与幅度约定（有限 / 全幅度）系数不同，隐式假定 BT.601 会导致颜色偏差且难以定位。
2. **布局紧凑化假设**：Android NDK `AIMAGE_FORMAT_YUV_420_888` 的三平面恒为 Y/U/V，**Y 平面 pixelStride=1，U/V 共享 rowStride 与 pixelStride**，且各平面可能带行填充（padding）；必须按 stride 读取，不能假设紧凑布局。

### 决策

- `ColorMatrix` 显式枚举 BT.601 / BT.709 × 有限 / 全幅度四种组合（`Bt601Limited` / `Bt601Full` / `Bt709Limited` / `Bt709Full`），系数由 `coeffs_for` 从字面常量按 `ColorMatrix` 现场计算，**必须显式传参**，无默认色彩空间。
- `PlaneDescriptor { data, row_stride, pixel_stride }` 显式携带 stride，所有平面一律按 `(row_stride, pixel_stride)` 采样；紧凑布局只是 `row_stride = 行字节数`、`pixel_stride = 1`（半平面色度为 2）的特例。NV21 为 VU 序、NV12 为 UV 序，同样显式区分。
- stride 非法（`pixel_stride = 0`、`row_stride` 放不下一行、缓冲区放不下全部行）一律以 `YuvError` 报错，绝不越界读取。

### 理由

- 显式色彩矩阵避免隐式 BT.601 假设，颜色语义由调用方裁决；
- 显式 stride 直接适配 NDK `YUV_420_888` 三平面非紧凑输出，免手动 repack，也避免紧凑布局误读；
- 全显式参数使 golden 测试可以对四种 `ColorMatrix` 逐一做差分验证。

### 后果

- **正面**：四格式 × 四布局 × 四种色彩矩阵组合行为可预测、可逐像素测试；非紧凑 stride 样本有专门测试覆盖。
- **负面**：调用方必须显式选择 `ColorMatrix` 与 stride，配置项略多；这是刻意换取的正确性。

## 4. 真实类型定义 + 真实函数实现

### 背景

开发早期曾考虑用 MoonBit 的 `declare` 特性先写规格：`declare` 只支持**函数签名、抽象类型、实现关系**，`struct` / `enum` / `trait` / `suberror` / 类型别名**不能**用 `declare` 声明（语言层面报 "Cannot declare a type with concrete definition"）；缺失实现的 `declare` 函数会产生 0068（`declaration_unimplemented`）告警。

### 决策

- **具体数据结构**（`YuvFrame` / `PlaneDescriptor` / `RgbImage` / `YuvFormat` / `RgbLayout` / `ColorMatrix` / `Rotation` / `ConvertConfig` / `YuvError` / `Channels` / `FrameConverter`）用**真实类型定义**——只有类型形状，不含业务逻辑（这也是语言的硬性要求）。
- **所有函数**（`to_rgb` / `rotate` / `mirror_x` / `RgbImage::{channels, bytes}`）用**真实函数实现**：非 `declare` 占位、非 `panic()` 伪实现，公开 API 配 `///` 文档注释（参数所有权、错误、线程约束、非目标）。

### 理由

- `declare` 占位会使 `moon check --deny-warn` 失败（0068 被升级为 error），门禁无法转绿；
- 伪实现违反"禁止伪实现"约束，且不可验收；
- 真实实现 + golden 测试才能给出"与参考实现逐像素一致"的证据。

### 后果

- **正面**：四道门禁 `moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check` 全绿（35 tests，0 条 0068）；`pkg.generated.mbti` API 快照与源码对账一致。
- **负面**：类型形状与函数签名已固定，**API 冻结后签名变更即破坏性变更**，需升主版本。

## 5. 后续可选依赖必须通过五门槛

### 背景

本库当前**零依赖**。后续可能的可选优化（如 SIMD 快路径，候选 `mizchi/simd` 等）都需要引入外部依赖；而无依据的大型依赖会带来网络 / 版本 / 许可耦合，破坏零依赖与独立可测性。

### 决策

当前不引入任何依赖；**后续任何新增依赖必须同时满足五条门槛**，并在本文件留痕：

1. **用途**：明确解决哪个能力，且本库无法以更小代价覆盖；
2. **许可**：SPDX 已核验、与 Apache-2.0 兼容；静态链接 / 再分发义务列明；
3. **维护**：版本、维护者、最后更新、构建状态、是否撤版（yanked）、是否遗留 manifest 格式；
4. **平台**：支持目标与本库全后端（`preferred_target = "wasm"`）一致，不破坏独立 `moon check`；
5. **风险**：登记风险，给出替代方案与移除成本。

### 理由

SIMD 快路径之类的优化收益未量化（wasm / native 两目标的一致性与收益均未验证），而引入依赖的成本是立即的；门槛制度把"想优化"与"敢依赖"解耦，先说明用途与维护风险再评估。

### 后果

- SIMD 快路径与 `moon bench` 阈值门禁保持为**后续可选优化，不改公开签名**；
- 任何未过五门槛的包只作**设计参照**（借鉴写法 / 算法思路），不进入 `moon.mod` / `moon.pkg`。

---

*以上决策源自开发期决策记录，已整合改写为自足表述；文中不含任何仓库外文件路径。*
