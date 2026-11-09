// Benchmark blocks for `moon bench`（本工具链 moon 0.1.20261104 实测可用：
// `bench` 语言关键字不存在，基准以 `test (b : @bench.T)` 块声明，`moon bench` 只运行此类块）。
//
// 运行：moon bench --target wasm
// 性能阈值门禁（fail-closed）：powershell -File tools/bench-gate.ps1
//
// 约定：被测帧在 bench 闭包外构造，计时只覆盖转换/几何变换本身；
// `b.keep` 防止结果被优化删除。阈值见 tools/bench-gate.ps1（含余量，防抖动）。

///|
/// 构造 w×h 紧凑 NV21 合成帧（确定性填充）。
fn nv21_bench_frame(w : Int32, h : Int32) -> @yuv.YuvFrame {
  let y = Bytes::makei(w * h, i => ((i * 31 + 7) % 256).to_byte())
  let cw = w / 2 + w % 2
  let chh = h / 2 + h % 2
  let uv = Bytes::makei(2 * cw * chh, i => ((i * 47 + 13) % 256).to_byte())
  @yuv.YuvFrame::{
    width: w,
    height: h,
    format: @yuv.YuvFormat::Nv21,
    planes: [
      @yuv.PlaneDescriptor::{ data: y, row_stride: w, pixel_stride: 1, },
      @yuv.PlaneDescriptor::{ data: uv, row_stride: 2 * cw, pixel_stride: 2, },
    ],
    timestamp_ns: 0UL,
  }
}

///|
/// 构造 w×h 紧凑 I420 合成帧（确定性填充）。
fn i420_bench_frame(w : Int32, h : Int32) -> @yuv.YuvFrame {
  let y = Bytes::makei(w * h, i => ((i * 31 + 7) % 256).to_byte())
  let cw = w / 2 + w % 2
  let chh = h / 2 + h % 2
  let u = Bytes::makei(cw * chh, i => ((i * 53 + 29) % 256).to_byte())
  let v = Bytes::makei(cw * chh, i => ((i * 59 + 31) % 256).to_byte())
  @yuv.YuvFrame::{
    width: w,
    height: h,
    format: @yuv.YuvFormat::I420,
    planes: [
      @yuv.PlaneDescriptor::{ data: y, row_stride: w, pixel_stride: 1, },
      @yuv.PlaneDescriptor::{ data: u, row_stride: cw, pixel_stride: 1, },
      @yuv.PlaneDescriptor::{ data: v, row_stride: cw, pixel_stride: 1, },
    ],
    timestamp_ns: 0UL,
  }
}

///|
/// 基准配置：BT.601 全幅度、RGBA、无几何变换、饱和输出。
fn bench_config() -> @yuv.ConvertConfig {
  @yuv.ConvertConfig::{
    matrix: @yuv.ColorMatrix::Bt601Full,
    layout: @yuv.RgbLayout::Rgba,
    rotation: @yuv.Rotation::D0,
    mirror_x: false,
    clamp: true,
  }
}

///|
/// 非抛错包装：bench 闭包要求总函数；基准输入为合法帧，错误不可达（返回 -1 哨兵）。
fn bench_to_rgb(frame : @yuv.YuvFrame, config : @yuv.ConvertConfig) -> Int32 {
  @yuv.RgbImage::bytes(@yuv.to_rgb(frame, config)).length() catch {
    _ => -1
  }
}

///|
fn bench_to_rgb_fast(
  frame : @yuv.YuvFrame,
  config : @yuv.ConvertConfig,
) -> Int32 {
  @yuv.RgbImage::bytes(@yuv.to_rgb_fast(frame, config)).length() catch {
    _ => -1
  }
}

///|
fn bench_rotate_d90(img : @yuv.RgbImage) -> Int32 {
  @yuv.RgbImage::bytes(@yuv.rotate(img, @yuv.Rotation::D90)).length() catch {
    _ => -1
  }
}

///|
fn bench_mirror_x(img : @yuv.RgbImage) -> Int32 {
  @yuv.RgbImage::bytes(@yuv.mirror_x(img)).length() catch {
    _ => -1
  }
}

///|
/// 转换内核基准：浮点参考路径 vs 定点快路径（同帧同配置）。
test (b : @bench.T) {
  let frame = nv21_bench_frame(640, 480)
  let config = bench_config()
  b.bench(name="to_rgb nv21 640x480", fn() {
    b.keep(bench_to_rgb(frame, config))
  })
  b.bench(name="to_rgb_fast nv21 640x480", fn() {
    b.keep(bench_to_rgb_fast(frame, config))
  })
}

///|
/// 三平面格式基准（I420，逐平面采样路径）。
test (b : @bench.T) {
  let frame = i420_bench_frame(640, 480)
  let config = bench_config()
  b.bench(name="to_rgb i420 640x480", fn() {
    b.keep(bench_to_rgb(frame, config))
  })
  b.bench(name="to_rgb_fast i420 640x480", fn() {
    b.keep(bench_to_rgb_fast(frame, config))
  })
}

///|
/// 几何变换基准（RGB 缓冲重排）。
test (b : @bench.T) {
  let img = @yuv.to_rgb_fast(nv21_bench_frame(640, 480), bench_config())
  b.bench(name="rotate d90 640x480", fn() { b.keep(bench_rotate_d90(img)) })
  b.bench(name="mirror_x 640x480", fn() { b.keep(bench_mirror_x(img)) })
}
