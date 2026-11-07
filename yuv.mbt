///|
/// YUV 转换基础库的类型与接口契约。
///
/// 本库是「纯计算 + 帧值类型」叶子库：无平台依赖、无 FFI、无外部句柄。
/// 跨模块帧数据契约见 docs/architecture.md（Wire Contract）：所有帧都以
/// `width / height / format / Bytes` 表达，由组合根在各库同名值类型间做轻量适配。
/// 本文件是数据结构定义与公开接口；像素计算与校验实现在 convert.mbt。

///|
/// 支持的 YUV 输入布局。
pub(all) enum YuvFormat {
  Nv21
  Nv12
  Yuv420888
  I420
}

///|
/// RGB 输出通道顺序。
pub(all) enum RgbLayout {
  Rgb
  Bgr
  Rgba
  Bgra
}

///|
/// 色彩空间系数（BT.601 / BT.709 / 全幅度变体）。显式传参，避免隐式假设。
pub(all) enum ColorMatrix {
  Bt601Limited
  Bt601Full
  Bt709Limited
  Bt709Full
}

///|
/// 旋转角度（顺时针）。
pub(all) enum Rotation {
  D0
  D90
  D180
  D270
}

///|
/// 单个 YUV 平面描述；`row_stride` / `pixel_stride` 用于 YUV_420_888 半平面/三平面读取。
pub(all) struct PlaneDescriptor {
  data : Bytes
  row_stride : Int32
  pixel_stride : Int32
}

///|
/// YUV 帧的中性值类型（与 `camera2` 侧同名类型结构一致，由组合根适配）。
pub(all) struct YuvFrame {
  width : Int32
  height : Int32
  format : YuvFormat
  planes : Array[PlaneDescriptor]
  timestamp_ns : UInt64
}

///|
/// RGB 图像的中性值类型（与 `pose` 侧同名类型结构一致，由组合根适配）。
pub(all) struct RgbImage {
  width : Int32
  height : Int32
  layout : RgbLayout
  data : Bytes
  timestamp_ns : UInt64
}

///|
/// 转换配置。
pub(all) struct ConvertConfig {
  matrix : ColorMatrix
  layout : RgbLayout
  rotation : Rotation
  mirror_x : Bool
  clamp : Bool
}

///|
/// YUV 错误模型：全部为可判定的输入错误，禁止越界读取与 panic。
#derive(Debug)
pub suberror YuvError {
  InvalidDimensions(Int32, Int32)
  PlaneCountMismatch(Int32, Int32)
  PlaneTooSmall(Int32, Int32)
  UnsupportedFormat(String)
  UnsupportedRotation(String)
  StrideMismatch(String)
  BufferSizeMismatch(Int32, Int32)
}

///|
pub extend YuvError with Debug::{to_repr}

///|
/// 输出通道数。
pub type Channels = Int32

///|
/// 纯计算转换契约；实现不得持有状态、不得做 I/O。
pub trait FrameConverter {
  fn to_rgb(Self, ConvertConfig) -> RgbImage raise YuvError
}

///|
/// YUV 帧 → RGB 图像。
///
/// - 参数：`frame` / `config` 均为只读纯值；不转移所有权，不缓存输入引用。
/// - 返回：新分配的 `RgbImage` 纯值，调用方持有；无句柄、无需释放。
/// - 色彩：按 `config.matrix` 的显式系数（BT.601 / BT.709 有限/全幅度）逐像素转换；
///   `config.clamp = true` 时结果饱和到 [0, 255]，否则按模 256 环绕进字节。
/// - 几何：先按 `config.rotation` 顺时针旋转，再按 `config.mirror_x` 水平翻转，
///   与 `rotate` / `mirror_x` 的组合语义一致；输出宽高随旋转交换。
/// - 错误：尺寸非法、平面数不符、stride 非法、缓冲区不足均以 `YuvError` 传播。
/// - 线程：无可变全局状态，纯函数，可并发调用。
/// - 非目标：不做相机取帧、不做编码、不做推理、不做 GPU/SIMD 调度（后续优化路径）。
pub fn to_rgb(
  frame : YuvFrame,
  config : ConvertConfig,
) -> RgbImage raise YuvError {
  validate_frame(frame)
  let ch = channels_of_layout(config.layout)
  let size64 = frame.width.to_int64() * frame.height.to_int64() * ch.to_int64()
  if size64 > 2147483647L {
    raise YuvError::InvalidDimensions(frame.width, frame.height)
  }
  let coeffs = coeffs_for(config.matrix)
  let (base, w, h) = convert_base(frame, config.layout, coeffs, config.clamp)
  let (data, ow, oh) = rotate_buffer(base, w, h, ch, config.rotation)
  let out_data = if config.mirror_x {
    mirror_buffer(data, ow, oh, ch)
  } else {
    data
  }
  RgbImage::{
    width: ow,
    height: oh,
    layout: config.layout,
    data: out_data,
    timestamp_ns: frame.timestamp_ns,
  }
}

///|
/// 旋转 RGB 图像（顺时针，返回新值，不修改输入）。
///
/// D0 返回内容一致的新 `RgbImage`；D90 / D270 输出宽高互换。
/// 旋转角来自封闭枚举 `Rotation`，四种取值均受支持；
/// `UnsupportedRotation` 保留给未来开放取值，当前不可达。
/// 输入缓冲长度必须精确等于 `width * height * channels`，否则 `BufferSizeMismatch`。
pub fn rotate(img : RgbImage, deg : Rotation) -> RgbImage raise YuvError {
  let ch = img.channels()
  check_rgb_buffer(img, ch)
  let (data, w, h) = rotate_buffer(img.data, img.width, img.height, ch, deg)
  RgbImage::{
    width: w,
    height: h,
    layout: img.layout,
    data,
    timestamp_ns: img.timestamp_ns,
  }
}

///|
/// 水平镜像 RGB 图像（左右翻转，返回新值，不修改输入）。
///
/// 输入缓冲长度必须精确等于 `width * height * channels`，否则 `BufferSizeMismatch`；
/// 尺寸非法返回 `InvalidDimensions`。
pub fn mirror_x(img : RgbImage) -> RgbImage raise YuvError {
  let ch = img.channels()
  check_rgb_buffer(img, ch)
  let data = mirror_buffer(img.data, img.width, img.height, ch)
  RgbImage::{
    width: img.width,
    height: img.height,
    layout: img.layout,
    data,
    timestamp_ns: img.timestamp_ns,
  }
}

///|
/// 返回每像素通道数，供组合根构造下游 `pose::RgbImage`。
pub fn RgbImage::channels(self : RgbImage) -> Channels {
  channels_of_layout(self.layout)
}

///|
/// 返回底层字节（只读引用语义，不复制）。
pub fn RgbImage::bytes(self : RgbImage) -> Bytes {
  self.data
}
