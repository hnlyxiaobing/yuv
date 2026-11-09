///|
/// 转换内核快路径：系数定点化（Q16.16）+ 256 项预计算查表。
/// 本文件不导出任何符号；公开入口 `to_rgb_fast` 见 `yuv.mbt`。
///
/// 数值契约（与 `convert.mbt` 的浮点参考路径逐像素对比）：
/// - **公差口径**：逐通道循环距离 `min(|a-b|, 256-|a-b|) ≤ 1 LSB`（模 256 意义下的 ±1）；
///   在 `clamp = true` 饱和模式下等价于普通绝对差 ≤ 1。
/// - 误差来源仅两处，均为定点化取整（round_half_up 到 1/65536 通道单位）：
///   LUT 项 ≤ 0.5/65536、系数 ≤ 0.5/65536（经 |色度偏移| ≤ 145 放大后 ≈ 0.0011），
///   传播上界 ≈ 0.0012 通道单位，远小于取整半距 0.5；
///   因此仅当浮点参考值恰落在 `k+0.5` 取整边界 ±0.0012 以内时，最终字节才可能相差 1 LSB。
/// - 取整语义与参考一致：0.5 向 +∞（`fx_round32` ≡ `round_half_up`）。
/// - 定点化收益：内层循环为整数加法 + 查表（Q32 累加、整数右移取整），
///   不含逐像素浮点乘法；输出在同一后端上可复现（与浮点环境差异无关）。
/// - 纯函数语义不变：定点表按调用现场构造，无任何可变全局状态。

///|
/// Q16.16 定点比例尺：1.0 记为 65536。
fn fx_one() -> Int32 {
  65536
}

///|
/// 定点系数表：Y / 色度各 256 项 Q16 查表 + 四个矩阵系数（Q16）。
priv struct FxTable {
  y_lut : FixedArray[Int32]
  c_lut : FixedArray[Int32]
  rv : Int32
  gu : Int32
  gv : Int32
  bu : Int32
}

///|
/// 由显式色彩矩阵构造定点表：每项 = round_half_up(浮点参考表达式 × 65536)，
/// 与 `convert.mbt` 的 `coeffs_for` 逐项同源（同一字面常量、同一公式）。
fn fx_table_for(matrix : ColorMatrix) -> FxTable {
  let c = coeffs_for(matrix)
  let s = fx_one().to_double()
  let y_lut = FixedArray::make(256, 0)
  for y in 0..<256 {
    y_lut.set(y, round_half_up((y.to_double() - c.y_off) * c.y_scale * s))
  }
  let c_lut = FixedArray::make(256, 0)
  for u in 0..<256 {
    c_lut.set(u, round_half_up((u.to_double() - 128.0) * c.c_scale * s))
  }
  FxTable::{
    y_lut,
    c_lut,
    rv: round_half_up(c.r_v * s),
    gu: round_half_up(c.g_u * s),
    gv: round_half_up(c.g_v * s),
    bu: round_half_up(c.b_u * s),
  }
}

///|
/// Q32 定点值 → 整数通道值：加半距后算术右移，
/// 与 `round_half_up` 同语义（0.5 向 +∞，负值同样成立）。
fn fx_round32(v : Int64) -> Int32 {
  ((v + 2147483648L) >> 32).to_int()
}

///|
/// 把整数通道值装入字节：`clamp_ = true` 饱和到 [0, 255]，否则按模 256 环绕。
/// 与 `pack_channel` 的后处理规则完全一致（定点路径复用同一装箱语义）。
fn pack_int(n : Int32, clamp_ : Bool) -> Byte {
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
/// 单像素 YUV → RGB（定点查表内核，标量路径）。
/// 索引前提同 `rgb_of_yuv`：y/u/v 均为 0..255 采样值，由采样方保证。
fn rgb_of_yuv_fx(
  y : Int32,
  u : Int32,
  v : Int32,
  t : FxTable,
  clamp_ : Bool,
) -> (Byte, Byte, Byte) {
  let yq = t.y_lut[y].to_int64()
  let uq = t.c_lut[u].to_int64()
  let vq = t.c_lut[v].to_int64()
  let base = yq << 16
  let r = fx_round32(base + t.rv.to_int64() * vq)
  let g = fx_round32(base - t.gu.to_int64() * uq - t.gv.to_int64() * vq)
  let b = fx_round32(base + t.bu.to_int64() * uq)
  (pack_int(r, clamp_), pack_int(g, clamp_), pack_int(b, clamp_))
}

///|
/// 把单像素三通道按布局写出（BGR/BGRA 交换 R/B，四通道补 alpha=0xFF）。
fn store_px(
  out : FixedArray[Byte],
  i : Int32,
  r : Byte,
  g : Byte,
  b : Byte,
  ch : Int32,
  bgr : Bool,
) -> Unit {
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

///|
/// 块内单像素直写：yq 为 Q16 亮度查表值，*_off 为块共享的 Q32 色度贡献偏移。
/// 与标量内核 `rgb_of_yuv_fx` 的整数运算逐位一致（加法结合律在 Int64 精确成立，
/// 无溢出：|base| ≤ 2^41、|off| ≤ 2^40），因此快/慢路径输出逐字节相等。
fn write_block_px(
  out : FixedArray[Byte],
  i : Int32,
  yq : Int32,
  r_off : Int64,
  g_off : Int64,
  b_off : Int64,
  ch : Int32,
  bgr : Bool,
  clamp_ : Bool,
) -> Unit {
  let base = yq.to_int64() << 16
  let r = pack_int(fx_round32(base + r_off), clamp_)
  let g = pack_int(fx_round32(base + g_off), clamp_)
  let b = pack_int(fx_round32(base + b_off), clamp_)
  store_px(out, i, r, g, b, ch, bgr)
}

///|
/// YUV 帧 → 紧凑 RGB 缓冲（源几何，定点批量快路径）。
/// 调用方须先通过 `validate_frame` 与输出尺寸校验（w*h*ch 在 Int32 内）。
///
/// 快路径结构（MoonBit 不暴露 SIMD 指令，以批量整数 + 查表 + 循环展开等效）：
/// - 2×2 批块：4:2:0 色度按块共享，uv 贡献每块一次提升为 Q32 整数偏移
///   （3 次乘法/块），块内 2×2 像素循环展开直写（每像素 1 次查表 + 3 次加移位）；
/// - 奇数尾列（w 奇）与奇数尾行（h 奇）回落到标量内核 `rgb_of_yuv_fx` 逐像素处理，
///   标量与批量两路算术逐位一致（见 `yuv_wbtest.mbt` 等价性测试）。
fn convert_base_fx(
  frame : YuvFrame,
  layout : RgbLayout,
  t : FxTable,
  clamp_ : Bool,
) -> (Bytes, Int32, Int32) {
  let w = frame.width
  let h = frame.height
  let ch = channels_of_layout(layout)
  let bgr = layout is Bgr || layout is Bgra
  let out = FixedArray::make(w * h * ch, b'\x00')
  let y_plane = frame.planes[0]
  for by in 0..<(h / 2) {
    for bx in 0..<(w / 2) {
      let (u, v) = sample_uv(frame, bx * 2, by * 2)
      let uq = t.c_lut[u].to_int64()
      let vq = t.c_lut[v].to_int64()
      let r_off = t.rv.to_int64() * vq
      let g_off = 0L - t.gu.to_int64() * uq - t.gv.to_int64() * vq
      let b_off = t.bu.to_int64() * uq
      let x0 = bx * 2
      let y0 = by * 2
      let i00 = (y0 * w + x0) * ch
      let i10 = i00 + w * ch
      write_block_px(
        out,
        i00,
        t.y_lut[sample_plane(y_plane, x0, y0)],
        r_off,
        g_off,
        b_off,
        ch,
        bgr,
        clamp_,
      )
      write_block_px(
        out,
        i00 + ch,
        t.y_lut[sample_plane(y_plane, x0 + 1, y0)],
        r_off,
        g_off,
        b_off,
        ch,
        bgr,
        clamp_,
      )
      write_block_px(
        out,
        i10,
        t.y_lut[sample_plane(y_plane, x0, y0 + 1)],
        r_off,
        g_off,
        b_off,
        ch,
        bgr,
        clamp_,
      )
      write_block_px(
        out,
        i10 + ch,
        t.y_lut[sample_plane(y_plane, x0 + 1, y0 + 1)],
        r_off,
        g_off,
        b_off,
        ch,
        bgr,
        clamp_,
      )
    }
  }
  // 奇数尾列（w 为奇数）：x = w-1，逐像素标量内核。
  if w % 2 == 1 {
    let x = w - 1
    for y in 0..<h {
      let yy = sample_plane(y_plane, x, y)
      let (u, v) = sample_uv(frame, x, y)
      let (r, g, b) = rgb_of_yuv_fx(yy, u, v, t, clamp_)
      store_px(out, (y * w + x) * ch, r, g, b, ch, bgr)
    }
  }
  // 奇数尾行（h 为奇数）：y = h-1，x 仅覆盖批块未达的偶数范围（角落像素已由尾列写入）。
  if h % 2 == 1 {
    let y = h - 1
    for x in 0..<(w / 2 * 2) {
      let yy = sample_plane(y_plane, x, y)
      let (u, v) = sample_uv(frame, x, y)
      let (r, g, b) = rgb_of_yuv_fx(yy, u, v, t, clamp_)
      store_px(out, (y * w + x) * ch, r, g, b, ch, bgr)
    }
  }
  (Bytes::from_array(out[:]), w, h)
}
