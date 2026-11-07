///|
/// 内部实现细节：色彩系数表、平面/缓冲区校验与几何变换。
/// 本文件不导出任何符号；公开接口见 `yuv.mbt`。
///
/// 约定（与测试共用）：
/// - 浮点转换结果按「四舍五入（0.5 向 +∞）」取整，再按 `clamp` 装入字节：
///   `clamp = true` 饱和到 [0, 255]，`clamp = false` 按模 256 环绕。
/// - 所有平面一律按 `(row_stride, pixel_stride)` 描述读取，紧凑布局只是
///   `row_stride = 行字节数`、`pixel_stride = 1`（半平面色度为 2）的特例。
/// - 校验通过后，采样索引与输出索引的上界均严格小于对应缓冲区长度，
///   因此逐字节读取不会越界，也不会 panic。

///|
/// 色彩转换系数，由 BT 标准基色系数 (Kr, Kb) 与幅度缩放推导：
/// - `y_off` / `y_scale`：Y' = (Y - y_off) * y_scale（有限幅度 y_off=16、y_scale=255/219）。
/// - `c_scale`：U' = (U - 128) * c_scale，V' = (V - 128) * c_scale（有限幅度 255/224）。
/// - R = Y' + r_v * V'；G = Y' - g_u * U' - g_v * V'；B = Y' + b_u * U'，
///   其中 r_v = 2(1-Kr)、g_u = 2(1-Kb)Kb/Kg、g_v = 2(1-Kr)Kr/Kg、b_u = 2(1-Kb)、Kg = 1-Kr-Kb。
priv struct YuvCoeffs {
  y_off : Double
  y_scale : Double
  c_scale : Double
  r_v : Double
  g_u : Double
  g_v : Double
  b_u : Double
}

///|
/// 按显式色彩空间给出系数（BT.601：Kr=0.299/Kb=0.114；BT.709：Kr=0.2126/Kb=0.0722）。
fn coeffs_for(matrix : ColorMatrix) -> YuvCoeffs {
  let (kr, kb, limited) = match matrix {
    Bt601Limited => (0.299, 0.114, true)
    Bt601Full => (0.299, 0.114, false)
    Bt709Limited => (0.2126, 0.0722, true)
    Bt709Full => (0.2126, 0.0722, false)
  }
  let kg = 1.0 - kr - kb
  let y_off = if limited { 16.0 } else { 0.0 }
  let y_scale = if limited { 255.0 / 219.0 } else { 1.0 }
  let c_scale = if limited { 255.0 / 224.0 } else { 1.0 }
  YuvCoeffs::{
    y_off,
    y_scale,
    c_scale,
    r_v: 2.0 * (1.0 - kr),
    g_u: 2.0 * (1.0 - kb) * kb / kg,
    g_v: 2.0 * (1.0 - kr) * kr / kg,
    b_u: 2.0 * (1.0 - kb),
  }
}

///|
/// 四舍五入，0.5 向 +∞ 取整：round_half_up(-0.5) = 0、round_half_up(0.5) = 1。
fn round_half_up(v : Double) -> Int32 {
  (v + 0.5).floor().to_int()
}

///|
/// 把单通道浮点值装入字节。`clamp_ = true` 饱和到 [0, 255]，否则按模 256 环绕。
fn pack_channel(v : Double, clamp_ : Bool) -> Byte {
  let n = round_half_up(v)
  let out = if clamp_ {
    if n < 0 {
      0
    } else if n > 255 {
      255
    } else {
      n
    }
  } else {
    (n % 256 + 256) % 256
  }
  out.to_byte()
}

///|
/// 单像素 YUV → RGB（未装箱浮点中间量）。
fn rgb_of_yuv(
  y : Int32,
  u : Int32,
  v : Int32,
  coeffs : YuvCoeffs,
  clamp_ : Bool,
) -> (Byte, Byte, Byte) {
  let yf = (y.to_double() - coeffs.y_off) * coeffs.y_scale
  let uf = (u.to_double() - 128.0) * coeffs.c_scale
  let vf = (v.to_double() - 128.0) * coeffs.c_scale
  let r = yf + coeffs.r_v * vf
  let g = yf - coeffs.g_u * uf - coeffs.g_v * vf
  let b = yf + coeffs.b_u * uf
  (pack_channel(r, clamp_), pack_channel(g, clamp_), pack_channel(b, clamp_))
}

///|
/// 每像素通道数：RGB/BGR 为 3，RGBA/BGRA 为 4。
fn channels_of_layout(layout : RgbLayout) -> Int32 {
  match layout {
    Rgb | Bgr => 3
    Rgba | Bgra => 4
  }
}

///|
/// 校验单个平面：stride 必须为正且放得下一行 `cols` 个采样（`group` 为每个采样
/// 占用的连续字节数，交错半平面为 2），缓冲区必须放得下全部 `rows` 行。
/// 通过后该平面的所有采样索引严格落在 `data` 界内。
fn check_plane(
  plane : PlaneDescriptor,
  index : Int32,
  cols : Int32,
  rows : Int32,
  group : Int32,
) -> Unit raise YuvError {
  let rs = plane.row_stride
  let ps = plane.pixel_stride
  if rs <= 0 || ps <= 0 || ps < group {
    raise YuvError::StrideMismatch(
      "plane \{index}: invalid stride (row_stride=\{rs}, pixel_stride=\{ps}, group=\{group})",
    )
  }
  let row_bytes = (cols - 1).to_int64() * ps.to_int64() + group.to_int64()
  if rs.to_int64() < row_bytes {
    raise YuvError::StrideMismatch(
      "plane \{index}: row_stride=\{rs} cannot hold \{row_bytes} bytes per row",
    )
  }
  let required = (rows - 1).to_int64() * rs.to_int64() + row_bytes
  let actual = plane.data.length()
  if actual.to_int64() < required {
    raise YuvError::PlaneTooSmall(index, actual)
  }
}

///|
/// 校验 YUV 帧：尺寸 → 平面数 → 各平面（下标升序）stride → 缓冲区长度。
/// 4:2:0 的色度网格为 ceil(width/2) × ceil(height/2)，故奇数尺寸合法。
fn validate_frame(frame : YuvFrame) -> Unit raise YuvError {
  let w = frame.width
  let h = frame.height
  if w <= 0 || h <= 0 {
    raise YuvError::InvalidDimensions(w, h)
  }
  let plane_count = match frame.format {
    Nv21 | Nv12 => 2
    Yuv420888 | I420 => 3
  }
  if frame.planes.length() != plane_count {
    raise YuvError::PlaneCountMismatch(plane_count, frame.planes.length())
  }
  let cw = w / 2 + w % 2
  let chh = h / 2 + h % 2
  check_plane(frame.planes[0], 0, w, h, 1)
  match frame.format {
    Nv21 | Nv12 => check_plane(frame.planes[1], 1, cw, chh, 2)
    I420 | Yuv420888 => {
      check_plane(frame.planes[1], 1, cw, chh, 1)
      check_plane(frame.planes[2], 2, cw, chh, 1)
    }
  }
}

///|
/// 校验 RGB 图像缓冲：尺寸为正、宽高乘积可寻址（Int32 内）、长度精确等于 w*h*ch。
fn check_rgb_buffer(img : RgbImage, ch : Int32) -> Unit raise YuvError {
  if img.width <= 0 || img.height <= 0 {
    raise YuvError::InvalidDimensions(img.width, img.height)
  }
  let expected64 = img.width.to_int64() * img.height.to_int64() * ch.to_int64()
  if expected64 > 2147483647L {
    raise YuvError::InvalidDimensions(img.width, img.height)
  }
  let expected = expected64.to_int()
  let actual = img.data.length()
  if expected != actual {
    raise YuvError::BufferSizeMismatch(expected, actual)
  }
}

///|
/// 按 (row_stride, pixel_stride) 读取平面采样，返回 0..255 的采样值。
fn sample_plane(plane : PlaneDescriptor, x : Int32, y : Int32) -> Int32 {
  plane.data.at(y * plane.row_stride + x * plane.pixel_stride).to_int()
}

///|
/// 读取亮度坐标 (x, y) 处的色度采样 (U, V)，色度坐标为 (x/2, y/2)。
/// NV21 交错平面为 VU 序、NV12 为 UV 序；I420 / YUV_420_888 为 Y/U/V 三平面。
fn sample_uv(frame : YuvFrame, x : Int32, y : Int32) -> (Int32, Int32) {
  let cx = x / 2
  let cy = y / 2
  match frame.format {
    Nv21 | Nv12 => {
      let p = frame.planes[1]
      let base = cy * p.row_stride + cx * p.pixel_stride
      let first = p.data.at(base).to_int()
      let second = p.data.at(base + 1).to_int()
      if frame.format is Nv21 {
        (second, first)
      } else {
        (first, second)
      }
    }
    I420 | Yuv420888 =>
      (
        sample_plane(frame.planes[1], cx, cy),
        sample_plane(frame.planes[2], cx, cy),
      )
  }
}

///|
/// YUV 帧 → 紧凑 RGB 缓冲（源几何）。调用方须先通过 `validate_frame`
/// 与输出尺寸校验（w*h*ch 在 Int32 内）。
fn convert_base(
  frame : YuvFrame,
  layout : RgbLayout,
  coeffs : YuvCoeffs,
  clamp_ : Bool,
) -> (Bytes, Int32, Int32) {
  let w = frame.width
  let h = frame.height
  let ch = channels_of_layout(layout)
  let bgr = layout is Bgr || layout is Bgra
  let out = FixedArray::make(w * h * ch, b'\x00')
  let y_plane = frame.planes[0]
  for y in 0..<h {
    for x in 0..<w {
      let yy = sample_plane(y_plane, x, y)
      let (u, v) = sample_uv(frame, x, y)
      let (r, g, b) = rgb_of_yuv(yy, u, v, coeffs, clamp_)
      let i = (y * w + x) * ch
      if bgr {
        out.set(i, b)
        out.set(i + 1, g)
        out.set(i + 2, r)
      } else {
        out.set(i, r)
        out.set(i + 1, g)
        out.set(i + 2, b)
      }
      if ch == 4 {
        out.set(i + 3, b'\xff')
      }
    }
  }
  (Bytes::from_array(out[:]), w, h)
}

///|
/// 顺时针旋转紧凑 RGB 缓冲。D0 原样返回；D90/D270 输出宽高互换。
fn rotate_buffer(
  data : Bytes,
  w : Int32,
  h : Int32,
  ch : Int32,
  deg : Rotation,
) -> (Bytes, Int32, Int32) {
  match deg {
    D0 => (data, w, h)
    D90 => {
      let out = FixedArray::make(w * h * ch, b'\x00')
      for y in 0..<h {
        for x in 0..<w {
          out.blit_from_bytes(
            (x * h + (h - 1 - y)) * ch,
            data,
            (y * w + x) * ch,
            ch,
          )
        }
      }
      (Bytes::from_array(out[:]), h, w)
    }
    D180 => {
      let out = FixedArray::make(w * h * ch, b'\x00')
      for y in 0..<h {
        for x in 0..<w {
          out.blit_from_bytes(
            ((h - 1 - y) * w + (w - 1 - x)) * ch,
            data,
            (y * w + x) * ch,
            ch,
          )
        }
      }
      (Bytes::from_array(out[:]), w, h)
    }
    D270 => {
      let out = FixedArray::make(w * h * ch, b'\x00')
      for y in 0..<h {
        for x in 0..<w {
          out.blit_from_bytes(
            ((w - 1 - x) * h + y) * ch,
            data,
            (y * w + x) * ch,
            ch,
          )
        }
      }
      (Bytes::from_array(out[:]), h, w)
    }
  }
}

///|
/// 水平翻转紧凑 RGB 缓冲（逐行反转像素顺序）。
fn mirror_buffer(data : Bytes, w : Int32, h : Int32, ch : Int32) -> Bytes {
  let out = FixedArray::make(w * h * ch, b'\x00')
  for y in 0..<h {
    for x in 0..<w {
      out.blit_from_bytes(
        (y * w + (w - 1 - x)) * ch,
        data,
        (y * w + x) * ch,
        ch,
      )
    }
  }
  Bytes::from_array(out[:])
}
