// Whitebox tests run within the package scope.
// Use them to validate internal helpers or invariants.
// Keep them focused; public behavior belongs in `_test.mbt`.

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
/// 捕获 `f` 抛出的 YuvError；未抛错则失败。
fn expect_yuv_error(
  f : () -> Unit raise YuvError,
  what : String,
) -> YuvError raise Failure {
  try f() catch {
    err => err
  } noraise {
    _ => fail("\{what}: expected YuvError")
  }
}

///|
fn plane(
  data : Array[Int32],
  row_stride : Int32,
  pixel_stride : Int32,
) -> PlaneDescriptor {
  let buf = Bytes::makei(data.length(), i => data[i].to_byte())
  PlaneDescriptor::{ data: buf, row_stride, pixel_stride, }
}

///|
fn config_of(matrix : ColorMatrix, clamp : Bool) -> ConvertConfig {
  ConvertConfig::{ matrix, layout: Rgb, rotation: D0, mirror_x: false, clamp, }
}

///|
fn nv21_frame(
  width : Int32,
  height : Int32,
  planes : Array[PlaneDescriptor],
) -> YuvFrame {
  YuvFrame::{ width, height, format: Nv21, planes, timestamp_ns: 0UL, }
}

///|
test "round_half_up rounds halves toward plus infinity" {
  check_int(round_half_up(0.5), 1, "0.5")
  check_int(round_half_up(1.5), 2, "1.5")
  check_int(round_half_up(2.49), 2, "2.49")
  check_int(round_half_up(-0.5), 0, "-0.5")
  check_int(round_half_up(-1.5), -1, "-1.5")
  check_int(round_half_up(-2.49), -2, "-2.49")
  check_int(round_half_up(0.0), 0, "0.0")
}

///|
test "pack_channel saturates when clamp is on" {
  check_int(pack_channel(300.6, true).to_int(), 255, "hi clamp")
  check_int(pack_channel(-5.5, true).to_int(), 0, "lo clamp")
  check_int(pack_channel(128.0, true).to_int(), 128, "mid")
  check_int(pack_channel(255.4, true).to_int(), 255, "hi edge")
  check_int(pack_channel(0.4, true).to_int(), 0, "lo edge")
}

///|
test "pack_channel wraps modulo 256 when clamp is off" {
  check_int(pack_channel(-1.0, false).to_int(), 255, "-1 wraps")
  check_int(pack_channel(-5.5, false).to_int(), 251, "-5 wraps")
  check_int(pack_channel(256.0, false).to_int(), 0, "256 wraps")
  check_int(pack_channel(300.6, false).to_int(), 45, "301 wraps")
  check_int(pack_channel(255.5, false).to_int(), 0, "256 wraps from .5")
  check_int(pack_channel(200.0, false).to_int(), 200, "in range")
}

///|
test "rejects non-positive frame dimensions" {
  let e1 = expect_yuv_error(
    () => to_rgb(nv21_frame(0, 2, []), config_of(Bt601Full, true)) |> ignore,
    "width 0",
  )
  match e1 {
    YuvError::InvalidDimensions(w, h) => {
      check_int(w, 0, "width")
      check_int(h, 2, "height")
    }
    _ => fail("expected InvalidDimensions")
  }
  let e2 = expect_yuv_error(
    () => to_rgb(nv21_frame(2, -1, []), config_of(Bt601Full, true)) |> ignore,
    "height -1",
  )
  match e2 {
    YuvError::InvalidDimensions(w, h) => {
      check_int(w, 2, "width")
      check_int(h, -1, "height")
    }
    _ => fail("expected InvalidDimensions")
  }
}

///|
test "rejects wrong plane count per format" {
  // NV21 需要 2 个平面。
  let frame = nv21_frame(2, 2, [plane([1, 2, 3, 4], 2, 1)])
  let e = expect_yuv_error(
    () => to_rgb(frame, config_of(Bt601Full, true)) |> ignore,
    "nv21 one plane",
  )
  match e {
    YuvError::PlaneCountMismatch(expected, actual) => {
      check_int(expected, 2, "expected")
      check_int(actual, 1, "actual")
    }
    _ => fail("expected PlaneCountMismatch")
  }
  // I420 需要 3 个平面。
  let i420 = YuvFrame::{
    width: 2,
    height: 2,
    format: I420,
    planes: [plane([1, 2, 3, 4], 2, 1), plane([5], 1, 1)],
    timestamp_ns: 0UL,
  }
  let e2 = expect_yuv_error(
    () => to_rgb(i420, config_of(Bt601Full, true)) |> ignore,
    "i420 two planes",
  )
  match e2 {
    YuvError::PlaneCountMismatch(expected, actual) => {
      check_int(expected, 3, "expected")
      check_int(actual, 2, "actual")
    }
    _ => fail("expected PlaneCountMismatch")
  }
}

///|
test "rejects too-small plane buffers" {
  // Y 平面 2x2 至少 4 字节，这里只有 3。
  let frame = nv21_frame(2, 2, [plane([1, 2, 3], 2, 1), plane([4, 5], 2, 2)])
  let e = expect_yuv_error(
    () => to_rgb(frame, config_of(Bt601Full, true)) |> ignore,
    "y plane short",
  )
  match e {
    YuvError::PlaneTooSmall(index, size) => {
      check_int(index, 0, "plane index")
      check_int(size, 3, "plane size")
    }
    _ => fail("expected PlaneTooSmall")
  }
  // 色度平面至少 2 字节，这里只有 1。
  let frame2 = nv21_frame(2, 2, [plane([1, 2, 3, 4], 2, 1), plane([9], 2, 2)])
  let e2 = expect_yuv_error(
    () => to_rgb(frame2, config_of(Bt601Full, true)) |> ignore,
    "chroma short",
  )
  match e2 {
    YuvError::PlaneTooSmall(index, size) => {
      check_int(index, 1, "plane index")
      check_int(size, 1, "plane size")
    }
    _ => fail("expected PlaneTooSmall")
  }
}

///|
test "rejects impossible strides without reading out of bounds" {
  // 巨大 row_stride + 小缓冲：必须报 PlaneTooSmall 而不是越界读取。
  let frame = nv21_frame(2, 2, [
    plane([1, 2, 3, 4], 1000000, 1),
    plane([4, 5], 2, 2),
  ])
  let e = expect_yuv_error(
    () => to_rgb(frame, config_of(Bt601Full, true)) |> ignore,
    "huge row_stride",
  )
  match e {
    YuvError::PlaneTooSmall(index, size) => {
      check_int(index, 0, "plane index")
      check_int(size, 4, "plane size")
    }
    _ => fail("expected PlaneTooSmall")
  }
}

///|
test "rejects invalid stride values" {
  // pixel_stride = 0。
  let e1 = expect_yuv_error(
    () => {
      to_rgb(
        nv21_frame(2, 2, [plane([1, 2, 3, 4], 2, 0), plane([4, 5], 2, 2)]),
        config_of(Bt601Full, true),
      )
      |> ignore
    },
    "zero pixel_stride",
  )
  assert_true(e1 is YuvError::StrideMismatch(_))
  // row_stride 放不下一行（2 像素至少 2 字节）。
  let e2 = expect_yuv_error(
    () => {
      to_rgb(
        nv21_frame(2, 2, [plane([1, 2, 3, 4], 1, 1), plane([4, 5], 2, 2)]),
        config_of(Bt601Full, true),
      )
      |> ignore
    },
    "row_stride too small",
  )
  assert_true(e2 is YuvError::StrideMismatch(_))
  // NV21 交错色度 pixel_stride 必须 >= 2（否则 V/U 采样重叠）。
  let e3 = expect_yuv_error(
    () => {
      to_rgb(
        nv21_frame(2, 2, [plane([1, 2, 3, 4], 2, 1), plane([4, 5], 2, 1)]),
        config_of(Bt601Full, true),
      )
      |> ignore
    },
    "interleaved pixel_stride 1",
  )
  assert_true(e3 is YuvError::StrideMismatch(_))
}

///|
test "rotate and mirror_x reject mismatched rgb buffer size" {
  let img = RgbImage::{
    width: 2,
    height: 2,
    layout: Rgb,
    data: Bytes::makei(5, i => i.to_byte()),
    timestamp_ns: 0UL,
  }
  let e1 = expect_yuv_error(
    () => rotate(img, D90) |> ignore,
    "rotate short buffer",
  )
  match e1 {
    YuvError::BufferSizeMismatch(expected, actual) => {
      check_int(expected, 12, "expected")
      check_int(actual, 5, "actual")
    }
    _ => fail("expected BufferSizeMismatch")
  }
  let e2 = expect_yuv_error(
    () => mirror_x(img) |> ignore,
    "mirror short buffer",
  )
  match e2 {
    YuvError::BufferSizeMismatch(expected, actual) => {
      check_int(expected, 12, "expected")
      check_int(actual, 5, "actual")
    }
    _ => fail("expected BufferSizeMismatch")
  }
  // 长度超出同样报错。
  let img_long = RgbImage::{
    width: 2,
    height: 2,
    layout: Rgb,
    data: Bytes::makei(13, i => i.to_byte()),
    timestamp_ns: 0UL,
  }
  let e3 = expect_yuv_error(
    () => mirror_x(img_long) |> ignore,
    "mirror long buffer",
  )
  match e3 {
    YuvError::BufferSizeMismatch(expected, actual) => {
      check_int(expected, 12, "expected")
      check_int(actual, 13, "actual")
    }
    _ => fail("expected BufferSizeMismatch")
  }
}

///|
test "rotate and mirror_x reject invalid or unaddressable dimensions" {
  let zero = RgbImage::{
    width: 0,
    height: 3,
    layout: Rgb,
    data: Bytes::new(0),
    timestamp_ns: 0UL,
  }
  let e1 = expect_yuv_error(() => rotate(zero, D0) |> ignore, "zero width")
  assert_true(e1 is YuvError::InvalidDimensions(0, 3))
  let e2 = expect_yuv_error(() => mirror_x(zero) |> ignore, "zero width mirror")
  assert_true(e2 is YuvError::InvalidDimensions(0, 3))
  // 65536x65536x3 超出 32 位可寻址范围：报 InvalidDimensions 而非溢出。
  let huge = RgbImage::{
    width: 65536,
    height: 65536,
    layout: Rgb,
    data: Bytes::new(0),
    timestamp_ns: 0UL,
  }
  let e3 = expect_yuv_error(() => rotate(huge, D0) |> ignore, "huge dims")
  assert_true(e3 is YuvError::InvalidDimensions(65536, 65536))
}

///|
test "chroma grid uses ceil for odd dimensions" {
  // 3x1 校验通过：色度网格为 ceil(3/2)=2 对（4 字节），且第三列取第二对。
  let frame = nv21_frame(3, 1, [
    plane([90, 128, 180], 3, 1),
    plane([90, 240, 200, 60], 4, 2),
  ])
  let img = to_rgb(frame, config_of(Bt601Full, true))
  check_int(img.width, 3, "width")
  check_int(img.height, 1, "height")
}
