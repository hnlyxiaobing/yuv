# yuv 测试系统设计（第一性原理）

> 建立：2026-11-17 ｜ 状态：设计生效，随开发文档逐包落地 ｜ 适用仓库：本仓库（独立自包含）
> 配套文档：[2026-11-17-explicit-pixel-fidelity-dev-plan.md](2026-11-17-explicit-pixel-fidelity-dev-plan.md)（`T-W*-*` 验收 ID 一一对应；B# 证据行见该文档 §0）

## 1. 第一性原理：本库的正确性是什么

本库的数学形态：

```text
(YuvFrame[planes + stride], ConvertConfig[matrix/layout/rotation/mirror/clamp])
  → RgbImage[width, height, layout, bytes, timestamp] | YuvError(7 类)
```

正确性不可约简为以下断言，每条必须有测试层承载：

| # | 断言 | 含义 | 反例（测试必须抓住） |
|---|---|---|---|
| A1 | 像素寻址忠实 | 按 `(row_stride,pixel_stride)` 采样，NV21 VU / NV12 UV / I420 三平面序正确；4:2:0 色度取 `ceil` 网格；输出布局通道序与 alpha 正确 | 误把 NV21 当 UV 序；非紧凑 stride 的 padding 被当成像素 |
| A2 | 完整性 fail-closed | 尺寸/平面数/stride/缓冲长度不符必报 7 类之一；不静默截断、不产出半张图 | 平面少一行却仍输出图像 |
| A3 | 边界纯净 | 参数全显式（矩阵/stride/几何），无隐式 BT.601 假设；只输出字节值，不产出缩放/增强/相机语义 | 未传矩阵时私自假定 BT.601 |
| A4 | 输入安全 | 任意尺寸/stride/平面字节不越界、不 panic；Int64 判定防 Int32 回绕 | `w*h*ch` 回绕成小值后小缓冲通过校验 |
| A5 | 契约稳定 | 4 顶层 fn、7 变体、trait/别名与快照一致；变更只加法 | README 漏错误变体或把格式写成别名 |
| A6 | 平台等价 | wasm 与 native 同输入同字节（浮点取整边界重点覆盖） | 浮点路径两目标在 k+0.5 边界舍入不同 |
| A7 | 快慢路径数值等价 | `to_rgb_fast` 与 `to_rgb` 逐通道循环距离 `min(|a-b|,256-|a-b|) ≤ 1 LSB`；clamp 下等价绝对差 ≤1 | 定点误差跨过取整边界造成 2 LSB 偏差 |
| A8 | 几何律 | 顺时针 D0/D90/D180/D270 索引映射、镜像逐行反转、先旋转后镜像组合正确、D0 返回新值、四通道 alpha 恒 `0xFF` | D90 用错偏移导致像素错位 |

设计推论：A1/A7/A8 → 性质测试 + 结构化 golden + 全边界扫描；A2/A4 → 截断变异 + 极端值；A5 → 五门禁与快照 diff；A6 → 双目标逐字节差分。

## 2. 测试分层

```text
L0 单元与程序化 fixture（现有 48 条：帧 builder + 期望字节 + 错误路径）
L1 性质与变异（变形律 / 9³ 定点边界 + 固定种子变异 / 截断扫描 / 极端 stride）
L2 受控黄金差分（tests/golden/ 确定性自产帧与逐字节期望；W3 建立）
L3 外部 oracle 差分（真实相机/标准库数值对照，许可与设备约束下可选，显式 SKIPPED）
L4 CLI 场景 E2E（无 CLI；退化为 4 fn 组合的预期/拒绝矩阵）
L5 元契约门禁（快照 / 7 变体簿记 / 双目标等价 / 变异自检 / 引用实存性 / 基准脚本 fail-closed）
```

断言×层承载表：

| 断言 | 主承载层 | 辅助层 |
|---|---|---|
| A1 像素寻址忠实 | L0 + L2 | L1（stride 变异） |
| A2 完整性 fail-closed | L0 + L5 | L1（截断） |
| A3 边界纯净 | L0 | L5（文案/参数扫描） |
| A4 输入安全 | L1 | L0（极端构造） |
| A5 契约稳定 | L5 | L2（防火墙逐字节） |
| A6 平台等价 | L5（双目标差分） | L2 |
| A7 快慢路径等价 | L0 + L1 | L2（全边界 golden） |
| A8 几何律 | L0 + L1 | L2（组合 golden） |

## 3. fixture 体系

| 类 | 形态 | 入库 | 许可 | 现状 |
|---|---|---|---|---|
| F-A 程序化构造 | 测试内 `r_frame()`/`r_frame_strided()`/`nv21_frame()`/矩阵配置 builder | 是 | 随仓库 | 已实现且被 48 条用例真实消费（B19） |
| F-B 受控文件 fixture | `tests/golden/*`（W3 计划） | 是 | 哈希登记 | 当前无目录、无死资产 |
| F-C 生成器资产 | 确定性帧 builder（紧凑/非紧凑/奇偶尺寸/四格式） | 是 | 自产 | W3 待建 |
| F-D 真实相机帧 | 仓库外设备/样本 | 否（红线） | 许可与隐私需确认 | L3 可选 + 显式 SKIPPED |

红线：F-D 永不入库；黄金字节变更须同步登记与逐字段记录；参考包系数来源只用泛称并标 [需联网核实]，不进入测试路径。
builder 能力清单：尺寸（1×1/奇×偶/偶×奇/大尺寸上界±1）；格式 × 平面数（2/3）；stride（紧凑、`row_stride > 行字节`、非法 0/负/过小、`pixel_stride` 1/2/非法 3）；矩阵 × 幅度四组；clamp 两模式；布局四组；几何四角 × 镜像；单像素采样值 9³ 全组合与 2048 固定种子采样。

## 4. L1 性质与变异

- 变形律 P1 幂等：同帧同配置双次调用输出逐字节相等；`mirror_x(mirror_x(img))` 回到原像素；`rotate(D0)` 返回新值且内容一致。
- 变形律 P2 几何逆律：`rotate(D90)` 后 `rotate(D270)` 回到原布局与原像素；`rotate(D180)` 两次幂等；旋转后宽高按 D90/D270 互换。
- 变形律 P3 组合律：`to_rgb` 的 `rotation+mirror_x` 结果等于 `to_rgb` 基帧后依次 `rotate`/`mirror_x`（既有用例已点状覆盖，W3 入 golden）。
- 变形律 P4 定点等价律：`to_rgb_fast` 与 `to_rgb` 循环距离 ≤1 LSB；定点批量与标量内核逐字节一致；紧凑/非紧凑 stride 采样序列一致时输出逐字节相同。
- 变形律 P5 装箱律：`clamp=true` 结果恒在 [0,255]；`clamp=false` 结果为模 256 环绕；四通道 alpha 恒 `0xFF`；`timestamp_ns` 恒透传。
- 变形律 P6 **防火墙律**：任一 W# 合入后旧 API 在既有 48 语料上输出逐字节不变、旧用例零改动全绿；`FrameConverter` impl 委托 `to_rgb`，语义零分叉。
- 位翻转：帧平面/配置字段单 bit 翻转 → 要么报声明错误变体，要么输出与翻转前不同；**格式依赖口径**：YUV 字节无 checksum，翻转后仍可能是合法像素，不得断言全部必错。
- 边界值矩阵：w/h 0/1/2/3/上界±1；`row_stride` 0/负/恰等于行字节/更大；`pixel_stride` 1/2/3；平面长度 `required-1/required/required+1`；采样值 0/128/255；色彩系数边界（黑/白/纯色）。
- 截断扫描：每个帧平面全前缀 + 结构边界（最后一行/列），只允许 7 类 `YuvError`，无 panic/挂起。
- 变异语料：固定种子随机替换/插入/删除平面字节，每轮 ≥1000 变异体；定点内核另有 9³ 全组合 + 2048 采样覆盖取整边界。

## 5. L3 oracle 矩阵 + R runner

| oracle | 差分对象 | 规范化口径 |
|---|---|---|
| 公开标准系数参考实现（可选） | 同一帧在 4 组矩阵下的逐通道值，只比双方声明的输出范围 | 取整规则明确后逐元素比较；范围/full-range 解释不一致时先对齐定义 |
| 真实相机帧（仓库外） | `to_rgb` 输出的视觉一致性与无 panic；不把真机系数当仓库内事实 | 报告哈希/日期/设备；缺失显式 SKIPPED |

纪律：oracle 缺失 → 显式 SKIPPED + 原因（退出码 78 口径），不得写成通过；R runner 样本路径 + 登记哈希 → 哈希不符拒绝执行 → 规范化差分 → 报告「本地已差分 + 哈希 + 日期」。

## 6. 覆盖矩阵与错误簿记

### 6.1 能力×场景×安全 覆盖矩阵

现状列来自 2026-11-17 P4 实测（B# 见开发文档 §0）；✓=已有用例，◐=点状/间接覆盖，✗=待建。

| ID | 能力/场景 | L0 | L1 | L2 | L3 | L4 | 现状(P4) | 缺口→W# |
|---|---|---|---|---|---|---|---|---|
| F1 | 4 格式 × 4 布局 | ✓ | ◐ | ✗ | ✗ | ✓ | 四格式与四布局均有断言（B7） | 全组合 golden→W3 |
| F2 | 非紧凑 stride 采样 | ✓ | ◐ | ✗ | ✗ | ✓ | 紧凑/strided 一致（B7） | stride 变异→W3 |
| F3 | 四矩阵 × 双装箱 | ✓ | ◐ | ✗ | ✗ | ✓ | 系数与 clamp/wrap（B8） | 全组合 golden→W3 |
| F4 | `to_rgb_fast` 定点 | ✓ | ✓ | ◐ | ✗ | ✓ | 9³+2048 采样 ≤1 LSB（B9） | 双目标差分→W3 |
| F5 | rotate/mirror 几何 | ✓ | ◐ | ✗ | ✗ | ✓ | 四角 + 组合（B10） | 逆律 golden→W3 |
| F6 | 访问器/时间戳 | ✓ | ✗ | ✗ | ✗ | ✓ | channels/bytes/timestamp 断言（B10） | 无 |
| F7 | 错误模型 7 变体 | ◐ | ✗ | ✗ | ✗ | ✓ | 显式簿记 **5/7**（B12） | 两死变体→W2 |
| F8 | 基准门禁脚本 | ◐ | ✗ | ✗ | ✗ | ✗ | 4 阈值 + 2 比值，本轮未复跑（B14） | 结构化报告→W4 |
| F9 | 公开 trait | ✗ | ✗ | ✗ | ✗ | ✗ | 零 impl（B13） | impl 加法→W2 |
| S1 | 预期场景端到端（帧→转换→几何→推理输入） | ✓ | | ◐ | | ✓ | 组合用例已有 | golden 固化→W3 |
| S2 | 安全拒绝（非法尺寸/平面/stride/缓冲） | ✓ | ◐ | | | ✓ | 7 变体中 5 类显式 | 死变体→W2；截断→W3 |
| C1 | 输入安全（无 panic/内存有界） | ◐ | ✗ | | | | Int64 防护在，无系统扫描（B11） | 截断变异→W3 |
| C2 | 防火墙（新包不改旧语义） | ◐ | ✗ | ✗ | | ◐ | 尚无固化 golden | T-W2-3/T-W3-5 |
| C3 | 许可红线（F-D 零入库） | ✓ | | | | | 零二进制（B6） | L3 显式 SKIPPED |
| C4 | 契约稳定（快照/索引/引用实存性） | ◐ | | | | | 双快照无漂移；索引/注释漂移（B2/B15） | 清理→W1；门禁→W3 |

C 行含防火墙（C2）与许可红线（C3）两行。

### 6.2 错误变体触发簿记（7/7 强制）

| 变体 | 触发 fixture（现状，2026-11-17） | 新增触发（待建） |
|---|---|---|
| `InvalidDimensions` | ✓ 宽/高 0 或负、超大尺寸 | 上界±1（W3） |
| `PlaneCountMismatch` | ✓ 2 平面格式给 3 平面、3 平面格式给 2 平面 | 无 |
| `PlaneTooSmall` | ✓ 各平面长度 `required-1`，含索引 0/1/2 断言 | 截断扫描（W3） |
| `UnsupportedFormat` | ✗ 零用例（封闭四值全部分派，当前不可达） | 构造级白盒断言 + 「预留」登记（W2） |
| `UnsupportedRotation` | ✗ 零用例（封闭四值全部分派，当前不可达） | 构造级白盒断言 + 「预留」登记（W2） |
| `StrideMismatch` | ✓ `row_stride/pixel_stride` 0/负/过小、NV21/NV12 色度 `pixel_stride≠2` | 极端 stride 变异（W3） |
| `BufferSizeMismatch` | ✓ `rotate`/`mirror_x` 输入缓冲长度不符 | 无 |

显式簿记现状 **5/7**（2026-11-17 实测）；W2 后达 **7/7**（两预留变体以构造级断言覆盖，不新增变体、不伪装成可达功能）。

### 6.3 恒等式断言（语义契约，全路径成立）

- `to_rgb` 输出尺寸：D0/D180 为 `(w,h)`，D90/D270 为 `(h,w)`；四通道 alpha 恒 `0xFF`；`timestamp_ns` 恒等于输入帧。
- 采样恒等式：`sample_uv(NV21)` 返回 `(V,U)`，`sample_uv(NV12/I420/YUV_420_888)` 返回 `(U,V)`；色度坐标恒为 `(x/2,y/2)`。
- 装箱恒等式：`clamp=true ⇒ 0≤byte≤255`；`clamp=false ⇒ byte = n mod 256`；round-half-up 对 ±0.5 分别为 0/1。
- 定点恒等式：`fx_round32` 与 `round_half_up` 同语义；批量块与标量内核逐字节一致；快慢路径循环距离恒 ≤1 LSB。
- 几何恒等式：`mirror_x ∘ mirror_x = id`；`rotate(D90) ∘ rotate(D270) = id`；`rotate(D0)` 返回新值但内容不变。
- **防火墙恒等式：任一 W# 合入后旧 API 在既有 48 语料上输出逐字节不变、旧用例零改动全绿**（W1/W5 文档包以旧用例零改动全绿为准）。

### 6.4 #skip 清单（显式单列，永不计入通过）

| 用例 | 位置 | 原因 |
|---|---|---|
| （无） | — | 当前基线零 `#skip`（2026-11-17 实测：源码 Grep `#skip`/SKIPPED = 0，`moon test` 48/48） |

计数口径：48 条声明（`yuv_test` 29 + `yuv_wbtest` 19）− 0 条 `#skip` = 48 执行（2026-11-17，wasm；native 亦 48/48、退出 0 但附沙箱提示，未复跑）；`--include-skipped` 结果单独报告。L3 真机/标准参考若落地，占位用例以 `#skip` 入库并在此表单列；SKIPPED 永不进入通过计数。

### 6.5 验收 ID 双向追溯表

| `T-W*-*` | W#（开发文档） | 矩阵缺口行 | 断言/层 |
|---|---|---|---|
| T-W1-1 引用实存性扫描零失效 | W1 | C4 | A5/L5 |
| T-W1-2 README 索引 ↔ mbti 逐条一致 | W1 | C4、F7 | A5/L5 |
| T-W1-3 五门禁绿 + 双快照 diff 空 | W1 | C4 | A5/L5 |
| T-W1-4 CHANGELOG 建立并登记 | W1 | C4 | A5/L5 |
| T-W2-1 两预留变体构造级显式断言 | W2 | F7、S2 | A2/L0 |
| T-W2-2 `FrameConverter` impl 与 `to_rgb` 逐字节一致 | W2 | F9 | A5/L0 |
| T-W2-3 旧 48 用例零改动全绿（防火墙） | W2 | C2 | A5/L5 |
| T-W2-4 快照 diff 纯加法、变体仍 7 个 | W2 | C4、F7 | A5/L5 |
| T-W3-1 golden 入库且被测试真实读取 | W3 | F1–F5、S1 | A1/L2 |
| T-W3-2 数值/stride 性质全绿 | W3 | F1、F2、F3、F4 | A7/L1 |
| T-W3-3 截断+变异扫描无 panic | W3 | C1 | A4/L1 |
| T-W3-4 wasm/native 值输出 diff=0 | W3 | F4、A6 | A6/L5 |
| T-W3-5 旧 48 用例零改动全绿（防火墙） | W3 | C2 | A5/L5 |
| T-W3-6 7/7 错误簿记门禁化 | W3 | F7 | A2/L5 |
| T-W4-1 基准报告字段齐全且缺失项 fail-closed | W4 | F8 | A5/L5 |
| T-W4-2 双目标基准 job 可跳过且不冒充通过 | W4 | F8 | A6/L5 |
| T-W4-3 阈值变更有复测记录与 CHANGELOG 登记 | W4 | F8 | A5/L5 |
| T-W5-1 README 非目标声明落盘 | W5 | C3 | A3/L5 |
| T-W5-2 测试文档对应行保持未实现 | W5 | C3 | A3/L5 |
| T-W5-3 无第三方依赖与零二进制入库复核 | W5 | C3 | A4/L5 |

未落地包对应行保持「未实现」标注，不预写通过。

## 7. L4 CLI 场景 E2E

本库无 CLI（`cmd/main` 为打印模板，B4）；L4 退化为库级组合 E2E：

| 场景 | 调用序列 | 断言要点 |
|---|---|---|
| 相机帧→RGBA（NDK 三平面） | `to_rgb(Yuv420888, {matrix:Bt601Limited,layout:Rgba,…})` | 宽度/高度/alpha 恒 `0xFF`/逐字节 golden |
| NV21 半平面 + 非紧凑 stride | `to_rgb(NV21, {layout:Bgr,…})` | padding 不参与采样；VU 序正确 |
| 预览镜像 | `mirror_x(img)` 或 `ConvertConfig.mirror_x=true` | 两种路径结果一致、逐行反转 |
| 旋转转正 | `rotate(img,D90)` / `D270` / `D180` | 宽高互换/倒置正确；D0 内容一致 |
| 定点快路径 | `to_rgb_fast` 同场景 | 与 `to_rgb` 循环距离 ≤1 LSB、几何一致 |
| 安全拒绝 | 非法尺寸/平面数/stride/长度 | 对应 `YuvError` 变体；无部分输出 |

记录行/JSON 契约冻结口径：本库 stdout/文件输出面为空；退出码矩阵不适用（无 CLI）；基准脚本退出语义为 PASS/FAIL（脚本层，非库契约）。

## 8. L5 元契约门禁

1. 快照门禁：`moon info` + `git diff --exit-code -- pkg.generated.mbti cmd/main/pkg.generated.mbti`（纯加法）。
2. 双目标等价：同一 builder 在 wasm/native 输出逐字节 diff=0；浮点边界先定位再定容差。
3. 错误簿记门禁：§6.2 的 7 变体 ↔ 测试代码双向核对，缺一即红（W2 后 7/7）。
4. 变异自检：注入 3 类缺陷（NV21 色度序反转 / stride 采样忽略 pixel_stride / 定点舍入改向零），套件必须变红后还原复绿。
5. 计数纪律：`#skip` 不计通过；过滤串以 `*` 结尾防空转假绿；基准 PASS 不进五门禁通过数。
6. 引用实存性扫描：`.mbt/.md/.yml/.ps1` 注释与文案引用的仓库内路径全部实存；README 索引与快照逐条一致；无工作区路径与兄弟模块符号。

## 9. CI 集成与执行入口

五门禁不变（CI 已固化）；L0/L1/L2 挂 `moon test`；L3/R/基准为脚本层可选 job，缺失显式 SKIPPED。
复验命令（本仓库根目录自包含）：

```bash
moon check --deny-warn
moon build
moon test
moon test --target native
moon fmt --check
moon info; git diff --exit-code -- pkg.generated.mbti cmd/main/pkg.generated.mbti
```

Windows 下 moon 把进度写 stderr，以退出码与 `Total tests: N, passed: N` 判定；语句分隔用 `;` 而非 `&&`。

## 10. 维护规则与验收清单

1. 新增 pub API ⇒ 同提交附 L0 样例 + L1 性质 + 矩阵/簿记更新；无测试不合入。
2. 新增格式/矩阵/几何路径 ⇒ 进截断扫描与全组合 golden 集。
3. golden/阈值变更 ⇒ 登记同提交更新，并附「仅受影响样本变化」对照；≤1 LSB 容差不放宽。
4. 每包合入 ⇒ 开发文档 DoD 勾选 + 矩阵现状刷新 + CHANGELOG 测试增量。
5. 「通过」须可复验：命令 + 日期 + 计数；SKIPPED 永远单列；定点与浮点结果分别报告。

落地验收：L0 ✓（48 条实跑）、L1 ◐（定点边界已有，其余待 W3）、L2 ✗（W3 待建）、L3 ✗（真机/标准 oracle 未配置，显式 SKIPPED）、L4 ✓（库级 E2E）、L5 ◐（快照与计数已验，7/7 簿记、双目标差分、变异自检待 W2/W3）、R ✗（零入库样本）；未落地包对应行保持「未实现」，不得预写通过。
