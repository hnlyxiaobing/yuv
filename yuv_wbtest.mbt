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
/// 定点内核 vs 浮点参考的单像素对比：返回三通道最大循环距离。
fn px_dist(
  y : Int32,
  u : Int32,
  v : Int32,
  c : YuvCoeffs,
  t : FxTable,
  clamp_ : Bool,
) -> Int32 {
  let (r1, g1, b1) = rgb_of_yuv(y, u, v, c, clamp_)
  let (r2, g2, b2) = rgb_of_yuv_fx(y, u, v, t, clamp_)
  let dr = cyclic_dist(r1.to_int(), r2.to_int())
  let dg = cyclic_dist(g1.to_int(), g2.to_int())
  let db = cyclic_dist(b1.to_int(), b2.to_int())
  if dr > dg {
    if dr > db {
      dr
    } else {
      db
    }
  } else if dg > db {
    dg
  } else {
    db
  }
}

///|
/// 对单个 (matrix, clamp) 组合做定点 vs 浮点公差扫描：
/// 边界值 9³ 全组合 + 2048 组确定性模采样，返回观测到的最大循环距离。
fn sweep_fx_vs_float(matrix : ColorMatrix, clamp_ : Bool) -> Int32 {
  let t = fx_table_for(matrix)
  let c = coeffs_for(matrix)
  let mut max_d = 0
  let edge = [0, 1, 2, 127, 128, 129, 253, 254, 255]
  for ai in 0..<edge.length() {
    for bi in 0..<edge.length() {
      for ci in 0..<edge.length() {
        let d = px_dist(edge[ai], edge[bi], edge[ci], c, t, clamp_)
        if d > max_d {
          max_d = d
        }
      }
    }
  }
  for i in 0..<2048 {
    let y = (i * 73 + 11) % 256
    let u = (i * 151 + 37) % 256
    let v = (i * 199 + 251) % 256
    let d = px_dist(y, u, v, c, t, clamp_)
    if d > max_d {
      max_d = d
    }
  }
  max_d
}

///|
test "fx_round32 rounds halves toward plus infinity" {
  check_int(fx_round32(0L), 0, "0.0")
  check_int(fx_round32(2147483648L), 1, "0.5")
  check_int(fx_round32(6442450944L), 2, "1.5")
  check_int(fx_round32(10737418240L), 3, "2.5")
  check_int(fx_round32(4294967296L), 1, "1.0")
  check_int(fx_round32(-2147483648L), 0, "-0.5")
  check_int(fx_round32(-6442450944L), -1, "-1.5")
  check_int(fx_round32(-4294967296L), -1, "-1.0")
}

///|
test "pack_int saturates when clamp is on" {
  check_int(pack_int(301, true).to_int(), 255, "hi clamp")
  check_int(pack_int(-6, true).to_int(), 0, "lo clamp")
  check_int(pack_int(128, true).to_int(), 128, "mid")
  check_int(pack_int(255, true).to_int(), 255, "hi edge")
  check_int(pack_int(0, true).to_int(), 0, "lo edge")
}

///|
test "pack_int wraps modulo 256 when clamp is off" {
  check_int(pack_int(-1, false).to_int(), 255, "-1 wraps")
  check_int(pack_int(-6, false).to_int(), 250, "-6 wraps")
  check_int(pack_int(256, false).to_int(), 0, "256 wraps")
  check_int(pack_int(301, false).to_int(), 45, "301 wraps")
  check_int(pack_int(200, false).to_int(), 200, "in range")
}

///|
test "fx tables approximate float reference terms within 1/65536" {
  let matrices = [Bt601Limited, Bt601Full, Bt709Limited, Bt709Full]
  for mi in 0..<matrices.length() {
    let t = fx_table_for(matrices[mi])
    let c = coeffs_for(matrices[mi])
    for y in 0..<256 {
      let want = (y.to_double() - c.y_off) * c.y_scale
      let got = t.y_lut[y].to_double() / fx_one().to_double()
      let diff = if got > want { got - want } else { want - got }
      if diff > 1.0 / 65536.0 {
        fail("matrix \{mi} y_lut[\{y}] off by \{diff}")
      }
    }
    for u in 0..<256 {
      let want = (u.to_double() - 128.0) * c.c_scale
      let got = t.c_lut[u].to_double() / fx_one().to_double()
      let diff = if got > want { got - want } else { want - got }
      if diff > 1.0 / 65536.0 {
        fail("matrix \{mi} c_lut[\{u}] off by \{diff}")
      }
    }
  }
}

///|
/// 公差口径断言：定点内核与浮点参考逐通道循环距离 ≤ 1 LSB。
test "fx kernel stays within 1 LSB of float reference (tolerance sweep)" {
  let matrices = [Bt601Limited, Bt601Full, Bt709Limited, Bt709Full]
  for mi in 0..<matrices.length() {
    for ci in 0..<2 {
      let clamp_ = ci == 1
      let max_d = sweep_fx_vs_float(matrices[mi], clamp_)
      if max_d > 1 {
        fail("matrix \{mi} clamp=\{clamp_}: max cyclic distance \{max_d} > 1")
      }
    }
  }
}

///|
/// 错误路径白盒测试：to_rgb_fast 对畸形输入一律走 YuvError，不 panic。
test "to_rgb_fast rejects malformed frames without panic" {
  // 尺寸非法。
  let e1 = expect_yuv_error(
    () => {
      to_rgb_fast(nv21_frame(0, 2, []), config_of(Bt601Full, true)) |> ignore
    },
    "width 0",
  )
  assert_true(e1 is YuvError::InvalidDimensions(0, 2))
  // 平面数不符（NV21 需要 2 个平面）。
  let e2 = expect_yuv_error(
    () => {
      to_rgb_fast(
        nv21_frame(2, 2, [plane([1, 2, 3, 4], 2, 1)]),
        config_of(Bt601Limited, true),
      )
      |> ignore
    },
    "plane count",
  )
  assert_true(e2 is YuvError::PlaneCountMismatch(2, 1))
  // 缓冲过小。
  let e3 = expect_yuv_error(
    () => {
      to_rgb_fast(
        nv21_frame(2, 2, [plane([1, 2, 3], 2, 1), plane([4, 5], 2, 2)]),
        config_of(Bt709Full, false),
      )
      |> ignore
    },
    "plane too small",
  )
  assert_true(e3 is YuvError::PlaneTooSmall(0, 3))
  // stride 非法（pixel_stride = 0）。
  let e4 = expect_yuv_error(
    () => {
      to_rgb_fast(
        nv21_frame(2, 2, [plane([1, 2, 3, 4], 2, 0), plane([4, 5], 2, 2)]),
        config_of(Bt709Limited, true),
      )
      |> ignore
    },
    "bad stride",
  )
  assert_true(e4 is YuvError::StrideMismatch(_))
  // 巨大 row_stride + 小缓冲：报 PlaneTooSmall 而非越界读取。
  let e5 = expect_yuv_error(
    () => {
      to_rgb_fast(
        nv21_frame(2, 2, [plane([1, 2, 3, 4], 1000000, 1), plane([4, 5], 2, 2)]),
        config_of(Bt601Full, true),
      )
      |> ignore
    },
    "huge row_stride",
  )
  assert_true(e5 is YuvError::PlaneTooSmall(0, 4))
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
