// Blackbox tests run against the package's public API. Use `@yuv` to import.
// Prefer high-level behaviors over implementation details.
// Run `moon test` to execute and `moon test --update` to refresh snapshots.

///|
/// 由整数字面量构造测试用 Bytes。
fn bytes_of(vals : Array[Int32]) -> Bytes {
  Bytes::makei(vals.length(), i => vals[i].to_byte())
}

///|
fn check_int(
  actual : Int32,
  expected : Int32,
  what : String,
) -> Unit raise Failure {
  if actual != expected {
    fail("\{what}: got \{actual}, want \{expected}")
  }
}

///|
/// 逐字节断言，期望值以 0..255 整数给出。
fn check_bytes(
  actual : Bytes,
  expected : Array[Int32],
  what : String,
) -> Unit raise Failure {
  if actual.length() != expected.length() {
    fail("\{what}: length \{actual.length()}, want \{expected.length()}")
  }
  for i in 0..<expected.length() {
    let got = actual.at(i).to_int()
    if got != expected[i] {
      fail("\{what}: byte[\{i}] = \{got}, want \{expected[i]}")
    }
  }
}

///|
fn check_same_bytes(
  actual : Bytes,
  expected : Bytes,
  what : String,
) -> Unit raise Failure {
  if actual.length() != expected.length() {
    fail("\{what}: length \{actual.length()}, want \{expected.length()}")
  }
  for i in 0..<expected.length() {
    let got = actual.at(i).to_int()
    let want = expected.at(i).to_int()
    if got != want {
      fail("\{what}: byte[\{i}] = \{got}, want \{want}")
    }
  }
}

///|
fn plane(
  data : Array[Int32],
  row_stride : Int32,
  pixel_stride : Int32,
) -> @yuv.PlaneDescriptor {
  @yuv.PlaneDescriptor::{ data: bytes_of(data), row_stride, pixel_stride, }
}

///|
fn config_of(
  matrix : @yuv.ColorMatrix,
  layout : @yuv.RgbLayout,
  rotation : @yuv.Rotation,
  mirror_x : Bool,
  clamp : Bool,
) -> @yuv.ConvertConfig {
  @yuv.ConvertConfig::{ matrix, layout, rotation, mirror_x, clamp, }
}

///|
/// BT.601 全幅度、RGB、无几何变换、饱和输出。
fn base_config() -> @yuv.ConvertConfig {
  config_of(
    @yuv.ColorMatrix::Bt601Full,
    @yuv.RgbLayout::Rgb,
    @yuv.Rotation::D0,
    false,
    true,
  )
}

///|
/// 样本 S：2x2 NV21，Y=[180,200,220,240]，V=150、U=100（全像素共享一对色度）。
fn s_frame(format : @yuv.YuvFormat, chroma : Array[Int32]) -> @yuv.YuvFrame {
  @yuv.YuvFrame::{
    width: 2,
    height: 2,
    format,
    planes: [plane([180, 200, 220, 240], 2, 1), plane(chroma, 2, 2)],
    timestamp_ns: 42UL,
  }
}

///|
/// 样本 S 的三平面变体（I420 / YUV_420_888 紧凑）。
fn s_frame_planar(format : @yuv.YuvFormat) -> @yuv.YuvFrame {
  @yuv.YuvFrame::{
    width: 2,
    height: 2,
    format,
    planes: [
      plane([180, 200, 220, 240], 2, 1),
      plane([100], 1, 1),
      plane([150], 1, 1),
    ],
    timestamp_ns: 42UL,
  }
}

///|
/// 样本 R：4x2 NV21（紧凑），Y=[10,20,30,40,50,60,70,80]，
/// 左半色度 U=110/V=100、右半 U=140/V=130。
fn r_frame() -> @yuv.YuvFrame {
  @yuv.YuvFrame::{
    width: 4,
    height: 2,
    format: @yuv.YuvFormat::Nv21,
    planes: [
      plane([10, 20, 30, 40, 50, 60, 70, 80], 4, 1),
      plane([100, 110, 130, 140], 4, 2),
    ],
    timestamp_ns: 7UL,
  }
}

///|
/// 样本 R 的 NV21 非紧凑变体：Y 行跨距 6（带填充），色度行跨距 6、采样间隔 2。
fn r_frame_strided() -> @yuv.YuvFrame {
  @yuv.YuvFrame::{
    width: 4,
    height: 2,
    format: @yuv.YuvFormat::Nv21,
    planes: [
      plane([10, 20, 30, 40, 99, 99, 50, 60, 70, 80, 99, 99], 6, 1),
      plane([100, 110, 130, 140, 99, 99], 6, 2),
    ],
    timestamp_ns: 7UL,
  }
}

///|
/// 样本 R 的 YUV_420_888 非紧凑变体：U/V 各自 pixel_stride=2、row_stride=6。
fn r_frame_888_strided() -> @yuv.YuvFrame {
  @yuv.YuvFrame::{
    width: 4,
    height: 2,
    format: @yuv.YuvFormat::Yuv420888,
    planes: [
      plane([10, 20, 30, 40, 99, 99, 50, 60, 70, 80, 99, 99], 6, 1),
      plane([110, 99, 140, 99, 99, 99], 6, 2),
      plane([100, 99, 130, 99, 99, 99], 6, 2),
    ],
    timestamp_ns: 7UL,
  }
}

///|
/// 样本 R 的基准 RGB（BT.601 全幅度、饱和输出），按行主序。
fn r_rgb_golden() -> Array[Int32] {
  [
    0, 36, 0, 0, 46, 0, 33, 24, 51, 43, 34, 61, 11, 76, 18, 21, 86, 28, 73, 64, 91,
    83, 74, 101,
  ]
}

///|
/// 2x3 手工 RGB 图（3 通道），像素值按行主序逐一可辨。
fn hand_rgb() -> @yuv.RgbImage {
  @yuv.RgbImage::{
    width: 2,
    height: 3,
    layout: @yuv.RgbLayout::Rgb,
    data: bytes_of([
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
    ]),
    timestamp_ns: 99UL,
  }
}

///|
test "to_rgb NV21 BT.601 full golden" {
  let img = @yuv.to_rgb(
    s_frame(@yuv.YuvFormat::Nv21, [150, 100]),
    base_config(),
  )
  check_int(img.width, 2, "width")
  check_int(img.height, 2, "height")
  assert_true(img.timestamp_ns == 42UL)
  check_bytes(
    @yuv.RgbImage::bytes(img),
    [211, 174, 130, 231, 194, 150, 251, 214, 170, 255, 234, 190],
    "bt601 full",
  )
}

///|
test "to_rgb BT.709 full golden differs from BT.601" {
  let config = config_of(
    @yuv.ColorMatrix::Bt709Full,
    @yuv.RgbLayout::Rgb,
    @yuv.Rotation::D0,
    false,
    true,
  )
  let img = @yuv.to_rgb(s_frame(@yuv.YuvFormat::Nv21, [150, 100]), config)
  check_bytes(
    @yuv.RgbImage::bytes(img),
    [215, 175, 128, 235, 195, 148, 255, 215, 168, 255, 235, 188],
    "bt709 full",
  )
}

///|
test "to_rgb BT.601 limited golden" {
  let config = config_of(
    @yuv.ColorMatrix::Bt601Limited,
    @yuv.RgbLayout::Rgb,
    @yuv.Rotation::D0,
    false,
    true,
  )
  let img = @yuv.to_rgb(s_frame(@yuv.YuvFormat::Nv21, [150, 100]), config)
  check_bytes(
    @yuv.RgbImage::bytes(img),
    [226, 184, 134, 249, 207, 158, 255, 231, 181, 255, 254, 204],
    "bt601 limited",
  )
}

///|
test "to_rgb BT.709 limited golden" {
  let config = config_of(
    @yuv.ColorMatrix::Bt709Limited,
    @yuv.RgbLayout::Rgb,
    @yuv.Rotation::D0,
    false,
    true,
  )
  let img = @yuv.to_rgb(s_frame(@yuv.YuvFormat::Nv21, [150, 100]), config)
  check_bytes(
    @yuv.RgbImage::bytes(img),
    [230, 185, 132, 254, 208, 155, 255, 232, 178, 255, 255, 202],
    "bt709 limited",
  )
}

///|
test "to_rgb NV12 reads interleaved UV order" {
  // NV12 交错色度为 UV 序：同一数值排列下应与 NV21(VU 序) 结果一致。
  let img = @yuv.to_rgb(
    s_frame(@yuv.YuvFormat::Nv12, [100, 150]),
    base_config(),
  )
  check_bytes(
    @yuv.RgbImage::bytes(img),
    [211, 174, 130, 231, 194, 150, 251, 214, 170, 255, 234, 190],
    "nv12",
  )
}

///|
test "to_rgb I420 planar golden" {
  let img = @yuv.to_rgb(s_frame_planar(@yuv.YuvFormat::I420), base_config())
  check_bytes(
    @yuv.RgbImage::bytes(img),
    [211, 174, 130, 231, 194, 150, 251, 214, 170, 255, 234, 190],
    "i420",
  )
}

///|
test "to_rgb YUV_420_888 compact golden" {
  let img = @yuv.to_rgb(
    s_frame_planar(@yuv.YuvFormat::Yuv420888),
    base_config(),
  )
  check_bytes(
    @yuv.RgbImage::bytes(img),
    [211, 174, 130, 231, 194, 150, 251, 214, 170, 255, 234, 190],
    "yuv420888 compact",
  )
}

///|
test "to_rgb NV21 compact vs non-compact strides agree" {
  let compact = @yuv.to_rgb(r_frame(), base_config())
  let strided = @yuv.to_rgb(r_frame_strided(), base_config())
  check_bytes(@yuv.RgbImage::bytes(compact), r_rgb_golden(), "nv21 compact")
  check_same_bytes(
    @yuv.RgbImage::bytes(strided),
    @yuv.RgbImage::bytes(compact),
    "nv21 strided",
  )
}

///|
test "to_rgb YUV_420_888 non-compact strides ignore padding" {
  // Y 行跨距 6、U/V pixel_stride=2 且带填充字节，输出应与紧凑样本一致。
  let strided = @yuv.to_rgb(r_frame_888_strided(), base_config())
  check_bytes(
    @yuv.RgbImage::bytes(strided),
    r_rgb_golden(),
    "yuv420888 strided",
  )
}

///|
test "to_rgb clamp true saturates to byte range" {
  let frame = @yuv.YuvFrame::{
    width: 2,
    height: 2,
    format: @yuv.YuvFormat::Nv21,
    planes: [plane([255, 255, 255, 255], 2, 1), plane([255, 0], 2, 2)],
    timestamp_ns: 0UL,
  }
  let config = config_of(
    @yuv.ColorMatrix::Bt601Limited,
    @yuv.RgbLayout::Rgb,
    @yuv.Rotation::D0,
    false,
    true,
  )
  let img = @yuv.to_rgb(frame, config)
  check_bytes(
    @yuv.RgbImage::bytes(img),
    [255, 225, 20, 255, 225, 20, 255, 225, 20, 255, 225, 20],
    "saturate hi",
  )
  let frame_lo = @yuv.YuvFrame::{
    width: 2,
    height: 2,
    format: @yuv.YuvFormat::Nv21,
    planes: [plane([0, 0, 0, 0], 2, 1), plane([0, 255], 2, 2)],
    timestamp_ns: 0UL,
  }
  let img_lo = @yuv.to_rgb(frame_lo, config)
  check_bytes(
    @yuv.RgbImage::bytes(img_lo),
    [0, 36, 238, 0, 36, 238, 0, 36, 238, 0, 36, 238],
    "saturate lo",
  )
}

///|
test "to_rgb clamp false wraps modulo 256" {
  let frame = @yuv.YuvFrame::{
    width: 2,
    height: 2,
    format: @yuv.YuvFormat::Nv21,
    planes: [plane([255, 255, 255, 255], 2, 1), plane([255, 0], 2, 2)],
    timestamp_ns: 0UL,
  }
  let config = config_of(
    @yuv.ColorMatrix::Bt601Limited,
    @yuv.RgbLayout::Rgb,
    @yuv.Rotation::D0,
    false,
    false,
  )
  let img = @yuv.to_rgb(frame, config)
  check_bytes(
    @yuv.RgbImage::bytes(img),
    [225, 225, 20, 225, 225, 20, 225, 225, 20, 225, 225, 20],
    "wrap hi",
  )
  let frame_lo = @yuv.YuvFrame::{
    width: 2,
    height: 2,
    format: @yuv.YuvFormat::Nv21,
    planes: [plane([0, 0, 0, 0], 2, 1), plane([0, 255], 2, 2)],
    timestamp_ns: 0UL,
  }
  let img_lo = @yuv.to_rgb(frame_lo, config)
  check_bytes(
    @yuv.RgbImage::bytes(img_lo),
    [33, 36, 238, 33, 36, 238, 33, 36, 238, 33, 36, 238],
    "wrap lo",
  )
}

///|
test "to_rgb layouts BGR RGBA BGRA pack channels" {
  let frame = s_frame(@yuv.YuvFormat::Nv21, [150, 100])
  let bgr = config_of(
    @yuv.ColorMatrix::Bt601Full,
    @yuv.RgbLayout::Bgr,
    @yuv.Rotation::D0,
    false,
    true,
  )
  check_bytes(
    @yuv.RgbImage::bytes(@yuv.to_rgb(frame, bgr)),
    [130, 174, 211, 150, 194, 231, 170, 214, 251, 190, 234, 255],
    "bgr",
  )
  let rgba = config_of(
    @yuv.ColorMatrix::Bt601Full,
    @yuv.RgbLayout::Rgba,
    @yuv.Rotation::D0,
    false,
    true,
  )
  check_bytes(
    @yuv.RgbImage::bytes(@yuv.to_rgb(frame, rgba)),
    [
      211, 174, 130, 255, 231, 194, 150, 255, 251, 214, 170, 255, 255, 234, 190,
      255,
    ],
    "rgba",
  )
  let bgra = config_of(
    @yuv.ColorMatrix::Bt601Full,
    @yuv.RgbLayout::Bgra,
    @yuv.Rotation::D0,
    false,
    true,
  )
  check_bytes(
    @yuv.RgbImage::bytes(@yuv.to_rgb(frame, bgra)),
    [
      130, 174, 211, 255, 150, 194, 231, 255, 170, 214, 251, 255, 190, 234, 255,
      255,
    ],
    "bgra",
  )
}

///|
test "to_rgb rotation D90 golden" {
  let config = config_of(
    @yuv.ColorMatrix::Bt601Full,
    @yuv.RgbLayout::Rgb,
    @yuv.Rotation::D90,
    false,
    true,
  )
  let img = @yuv.to_rgb(r_frame(), config)
  check_int(img.width, 2, "width")
  check_int(img.height, 4, "height")
  check_bytes(
    @yuv.RgbImage::bytes(img),
    [
      11, 76, 18, 0, 36, 0, 21, 86, 28, 0, 46, 0, 73, 64, 91, 33, 24, 51, 83, 74,
      101, 43, 34, 61,
    ],
    "rotate d90",
  )
}

///|
test "to_rgb rotation D180 golden" {
  let config = config_of(
    @yuv.ColorMatrix::Bt601Full,
    @yuv.RgbLayout::Rgb,
    @yuv.Rotation::D180,
    false,
    true,
  )
  let img = @yuv.to_rgb(r_frame(), config)
  check_bytes(
    @yuv.RgbImage::bytes(img),
    [
      83, 74, 101, 73, 64, 91, 21, 86, 28, 11, 76, 18, 43, 34, 61, 33, 24, 51, 0,
      46, 0, 0, 36, 0,
    ],
    "rotate d180",
  )
}

///|
test "to_rgb rotation D270 golden" {
  let config = config_of(
    @yuv.ColorMatrix::Bt601Full,
    @yuv.RgbLayout::Rgb,
    @yuv.Rotation::D270,
    false,
    true,
  )
  let img = @yuv.to_rgb(r_frame(), config)
  check_bytes(
    @yuv.RgbImage::bytes(img),
    [
      43, 34, 61, 83, 74, 101, 33, 24, 51, 73, 64, 91, 0, 46, 0, 21, 86, 28, 0, 36,
      0, 11, 76, 18,
    ],
    "rotate d270",
  )
}

///|
test "to_rgb mirror_x golden" {
  let config = config_of(
    @yuv.ColorMatrix::Bt601Full,
    @yuv.RgbLayout::Rgb,
    @yuv.Rotation::D0,
    true,
    true,
  )
  let img = @yuv.to_rgb(r_frame(), config)
  check_bytes(
    @yuv.RgbImage::bytes(img),
    [
      43, 34, 61, 33, 24, 51, 0, 46, 0, 0, 36, 0, 83, 74, 101, 73, 64, 91, 21, 86,
      28, 11, 76, 18,
    ],
    "mirror_x",
  )
}

///|
test "to_rgb rotation D90 then mirror_x golden" {
  let config = config_of(
    @yuv.ColorMatrix::Bt601Full,
    @yuv.RgbLayout::Rgb,
    @yuv.Rotation::D90,
    true,
    true,
  )
  let img = @yuv.to_rgb(r_frame(), config)
  check_bytes(
    @yuv.RgbImage::bytes(img),
    [
      0, 36, 0, 11, 76, 18, 0, 46, 0, 21, 86, 28, 33, 24, 51, 73, 64, 91, 43, 34,
      61, 83, 74, 101,
    ],
    "rotate d90 + mirror",
  )
}

///|
test "to_rgb geometry equals rotate then mirror_x pipeline" {
  let base = @yuv.to_rgb(r_frame(), base_config())
  let expected = @yuv.mirror_x(@yuv.rotate(base, @yuv.Rotation::D90))
  let config = config_of(
    @yuv.ColorMatrix::Bt601Full,
    @yuv.RgbLayout::Rgb,
    @yuv.Rotation::D90,
    true,
    true,
  )
  let actual = @yuv.to_rgb(r_frame(), config)
  check_same_bytes(
    @yuv.RgbImage::bytes(actual),
    @yuv.RgbImage::bytes(expected),
    "pipeline equality",
  )
  assert_true(actual.width == expected.width)
  assert_true(actual.height == expected.height)
}

///|
test "to_rgb accepts odd dimensions with ceil chroma grid" {
  // 3x1：色度网格 ceil(3/2)=2 对，第三列像素取第二对色度。
  let frame = @yuv.YuvFrame::{
    width: 3,
    height: 1,
    format: @yuv.YuvFormat::Nv21,
    planes: [plane([90, 128, 180], 3, 1), plane([90, 240, 200, 60], 4, 2)],
    timestamp_ns: 0UL,
  }
  let img = @yuv.to_rgb(frame, base_config())
  check_bytes(
    @yuv.RgbImage::bytes(img),
    [37, 79, 255, 75, 117, 255, 255, 152, 60],
    "odd 3x1",
  )
}

///|
test "to_rgb minimal 1x1 frame" {
  let frame = @yuv.YuvFrame::{
    width: 1,
    height: 1,
    format: @yuv.YuvFormat::Nv21,
    planes: [plane([200], 1, 1), plane([150, 100], 2, 2)],
    timestamp_ns: 5UL,
  }
  let img = @yuv.to_rgb(frame, base_config())
  check_bytes(@yuv.RgbImage::bytes(img), [231, 194, 150], "1x1")
}

///|
test "rotate RGB image D0 D90 D180 D270 goldens" {
  let img = hand_rgb()
  let d0 = @yuv.rotate(img, @yuv.Rotation::D0)
  check_int(d0.width, 2, "d0 width")
  check_int(d0.height, 3, "d0 height")
  check_bytes(
    @yuv.RgbImage::bytes(d0),
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17],
    "d0",
  )
  assert_true(d0.timestamp_ns == 99UL)
  let d90 = @yuv.rotate(img, @yuv.Rotation::D90)
  check_int(d90.width, 3, "d90 width")
  check_int(d90.height, 2, "d90 height")
  check_bytes(
    @yuv.RgbImage::bytes(d90),
    [12, 13, 14, 6, 7, 8, 0, 1, 2, 15, 16, 17, 9, 10, 11, 3, 4, 5],
    "d90",
  )
  let d180 = @yuv.rotate(img, @yuv.Rotation::D180)
  check_bytes(
    @yuv.RgbImage::bytes(d180),
    [15, 16, 17, 12, 13, 14, 9, 10, 11, 6, 7, 8, 3, 4, 5, 0, 1, 2],
    "d180",
  )
  let d270 = @yuv.rotate(img, @yuv.Rotation::D270)
  check_int(d270.width, 3, "d270 width")
  check_int(d270.height, 2, "d270 height")
  check_bytes(
    @yuv.RgbImage::bytes(d270),
    [3, 4, 5, 9, 10, 11, 15, 16, 17, 0, 1, 2, 6, 7, 8, 12, 13, 14],
    "d270",
  )
}

///|
test "mirror_x RGB image flips columns" {
  let img = hand_rgb()
  let out = @yuv.mirror_x(img)
  check_int(out.width, 2, "width")
  check_int(out.height, 3, "height")
  check_bytes(
    @yuv.RgbImage::bytes(out),
    [3, 4, 5, 0, 1, 2, 9, 10, 11, 6, 7, 8, 15, 16, 17, 12, 13, 14],
    "mirror_x",
  )
  // 输入不变。
  check_bytes(
    @yuv.RgbImage::bytes(img),
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17],
    "input untouched",
  )
}

///|
test "mirror_x keeps RGBA channel order and alpha" {
  let img = @yuv.RgbImage::{
    width: 2,
    height: 2,
    layout: @yuv.RgbLayout::Rgba,
    data: bytes_of([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]),
    timestamp_ns: 1UL,
  }
  let out = @yuv.mirror_x(img)
  check_int(img.channels(), 4, "channels")
  check_bytes(
    @yuv.RgbImage::bytes(out),
    [5, 6, 7, 8, 1, 2, 3, 4, 13, 14, 15, 16, 9, 10, 11, 12],
    "mirror rgba",
  )
  let rot = @yuv.rotate(img, @yuv.Rotation::D180)
  check_bytes(
    @yuv.RgbImage::bytes(rot),
    [13, 14, 15, 16, 9, 10, 11, 12, 5, 6, 7, 8, 1, 2, 3, 4],
    "rotate rgba",
  )
}

///|
/// 循环距离（模 256）：公差口径 `min(|a-b|, 256-|a-b|)`。
fn cyclic_dist(a : Int32, b : Int32) -> Int32 {
  let d = if a > b { a - b } else { b - a }
  if d < 256 - d {
    d
  } else {
    256 - d
  }
}

///|
/// 逐通道断言快/慢两路输出的循环距离 ≤ 1 LSB（公差口径）。
fn check_within_1lsb(
  actual : @yuv.RgbImage,
  expected : @yuv.RgbImage,
  what : String,
) -> Unit raise Failure {
  check_int(actual.width, expected.width, "\{what}: width")
  check_int(actual.height, expected.height, "\{what}: height")
  let a = @yuv.RgbImage::bytes(actual)
  let e = @yuv.RgbImage::bytes(expected)
  if a.length() != e.length() {
    fail("\{what}: length \{a.length()}, want \{e.length()}")
  }
  for i in 0..<a.length() {
    let d = cyclic_dist(a.at(i).to_int(), e.at(i).to_int())
    if d > 1 {
      fail(
        "\{what}: byte[\{i}] cyclic distance \{d} > 1 (got \{a.at(i).to_int()}, want \{e.at(i).to_int()})",
      )
    }
  }
}

///|
/// 逐字节断言两帧完全一致。
fn check_exact(
  actual : @yuv.RgbImage,
  expected : @yuv.RgbImage,
  what : String,
) -> Unit raise Failure {
  check_int(actual.width, expected.width, "\{what}: width")
  check_int(actual.height, expected.height, "\{what}: height")
  check_same_bytes(
    @yuv.RgbImage::bytes(actual),
    @yuv.RgbImage::bytes(expected),
    what,
  )
}

///|
test "to_rgb_fast matches to_rgb within 1 LSB cyclic distance" {
  let matrices = [
    @yuv.ColorMatrix::Bt601Limited,
    @yuv.ColorMatrix::Bt601Full,
    @yuv.ColorMatrix::Bt709Limited,
    @yuv.ColorMatrix::Bt709Full,
  ]
  let frames = [
    s_frame(@yuv.YuvFormat::Nv21, [150, 100]),
    s_frame(@yuv.YuvFormat::Nv12, [100, 150]),
    s_frame_planar(@yuv.YuvFormat::I420),
    s_frame_planar(@yuv.YuvFormat::Yuv420888),
    r_frame(),
    r_frame_strided(),
    r_frame_888_strided(),
  ]
  for mi in 0..<matrices.length() {
    for ci in 0..<2 {
      let clamp_ = ci == 1
      for fi in 0..<frames.length() {
        let config = config_of(
          matrices[mi],
          @yuv.RgbLayout::Rgb,
          @yuv.Rotation::D0,
          false,
          clamp_,
        )
        let slow = @yuv.to_rgb(frames[fi], config)
        let fast = @yuv.to_rgb_fast(frames[fi], config)
        check_within_1lsb(
          fast,
          slow,
          "frame \{fi} matrix \{mi} clamp \{clamp_}",
        )
        assert_true(fast.timestamp_ns == slow.timestamp_ns)
      }
    }
  }
}

///|
test "to_rgb_fast compact vs strided frames agree exactly" {
  // 同一像素值、不同 stride 布局，快路径读取的采样序列一致，输出必须逐字节相同。
  let config = config_of(
    @yuv.ColorMatrix::Bt601Full,
    @yuv.RgbLayout::Rgba,
    @yuv.Rotation::D0,
    false,
    true,
  )
  let compact = @yuv.to_rgb_fast(r_frame(), config)
  let strided = @yuv.to_rgb_fast(r_frame_strided(), config)
  check_exact(strided, compact, "nv21 compact vs strided")
  let strided_888 = @yuv.to_rgb_fast(r_frame_888_strided(), config)
  check_exact(strided_888, compact, "yuv420888 strided vs nv21 compact")
}

///|
test "to_rgb_fast geometry equals rotate then mirror_x pipeline" {
  let base_config = config_of(
    @yuv.ColorMatrix::Bt601Full,
    @yuv.RgbLayout::Rgb,
    @yuv.Rotation::D0,
    false,
    true,
  )
  let base = @yuv.to_rgb_fast(r_frame(), base_config)
  let expected = @yuv.mirror_x(@yuv.rotate(base, @yuv.Rotation::D90))
  let config = config_of(
    @yuv.ColorMatrix::Bt601Full,
    @yuv.RgbLayout::Rgb,
    @yuv.Rotation::D90,
    true,
    true,
  )
  let actual = @yuv.to_rgb_fast(r_frame(), config)
  check_exact(actual, expected, "fast pipeline equality")
}

///|
test "channels and bytes accessors" {
  let rgb = @yuv.RgbImage::{
    width: 1,
    height: 1,
    layout: @yuv.RgbLayout::Rgb,
    data: bytes_of([7, 8, 9]),
    timestamp_ns: 0UL,
  }
  check_int(rgb.channels(), 3, "rgb channels")
  check_bytes(@yuv.RgbImage::bytes(rgb), [7, 8, 9], "bytes")
  let bgr = @yuv.RgbImage::{
    width: 1,
    height: 1,
    layout: @yuv.RgbLayout::Bgr,
    data: bytes_of([7, 8, 9]),
    timestamp_ns: 0UL,
  }
  check_int(bgr.channels(), 3, "bgr channels")
  let bgra = @yuv.RgbImage::{
    width: 1,
    height: 1,
    layout: @yuv.RgbLayout::Bgra,
    data: bytes_of([7, 8, 9, 10]),
    timestamp_ns: 0UL,
  }
  check_int(bgra.channels(), 4, "bgra channels")
  check_bytes(@yuv.RgbImage::bytes(bgra), [7, 8, 9, 10], "bgra bytes")
}
