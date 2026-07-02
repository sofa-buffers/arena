#!/usr/bin/env bash
# Provisional footprint probe for the two rust-embedded codecs.
#
# Prints ONE line per impl:
#   FOOTPRINT lang=rust-embedded impl=<sofab|micropb> text=<b> rodata=<b> data=<b> bss=<b>
#
# Methodology (kept consistent with the C target's object-sum, and between the
# two impls): each codec is compiled as a `crate-type=["staticlib"]` release lib
# with the size profile (opt-level="z", lto=true, panic="abort"), then we sum the
# .text/.rodata/.data/.bss sections of the resulting `.a` via `size -A`. A Rust
# staticlib archive bundles the crate objects plus its no_std deps but NOT libc
# (that's supplied at final link), so this is the direct analog of the C
# object-sum. Like the C method it counts the WHOLE archive (no --gc-sections),
# so it OVER-counts what real firmware would keep after dead-strip.
#
# CAVEAT (provisional): the fair metric is a bare-metal ARM --gc-sections build
# (currently parked). Also, the two impls are not perfectly symmetric:
#   * micropb  — the .a includes the actual generated FullScaleExample codec
#                (micropb-gen output) + micropb runtime + heapless, exercised
#                via enc/dec of the real message. Faithful codec footprint.
#   * sofab    — the sofabgen-generated message crate carries serde/Vec/String
#                (std) and cannot be compiled no_std as-is, so the sofab number
#                is the corelib-rs-no-std codec exercised through a synthetic
#                no_std harness covering every wire type the schema uses (the
#                generated marshal/decode are thin wrappers over exactly these
#                OStream/IStream calls). Representative, not the generated glue.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SOFAB_RS_CORELIB="$ROOT/vendor/corelib-rs-no-std"

export CARGO_HOME="${CARGO_HOME:-/usr/local/cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-/usr/local/rustup}"
export PATH="/usr/local/cargo/bin:$HOME/.cargo/bin:$PATH"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# sum_sections <archive> -> "text rodata data bss"
sum_sections() {
    size -A "$1" | awk '
        $1 ~ /^\.text/   { text += $2 }
        $1 ~ /^\.rodata/ { rod  += $2 }
        $1 ~ /^\.data/   { dat  += $2 }
        $1 ~ /^\.bss/    { bss  += $2 }
        END { printf "%d %d %d %d\n", text, rod, dat, bss }'
}

emit() { # impl "text rodata data bss"
    local impl="$1"; read -r t r d b <<<"$2"
    printf 'FOOTPRINT lang=rust-embedded impl=%s text=%s rodata=%s data=%s bss=%s\n' \
        "$impl" "$t" "$r" "$d" "$b"
}

PROFILE='[profile.release]
opt-level = "z"
lto = true
codegen-units = 1
panic = "abort"'

# ---------------------------------------------------------------------------
# sofab: no_std staticlib exercising the corelib codec (all wire types).
# ---------------------------------------------------------------------------
SF="$WORK/sofab_fp"; mkdir -p "$SF/src"
cat > "$SF/Cargo.toml" <<EOF
[package]
name = "sofab_fp"
version = "0.0.0"
edition = "2021"
[lib]
crate-type = ["staticlib"]
[dependencies]
sofab = { package = "sofa-buffers-corelib-no-std", path = "$SOFAB_RS_CORELIB", default-features = false, features = ["array", "fixlen", "fp64", "sequence", "value64"] }
$PROFILE
EOF
cat > "$SF/src/lib.rs" <<'EOF'
#![no_std]
use core::panic::PanicInfo;
use sofab::{ArrayKind, Id, IStream, OStream, Signed, Unsigned, Visitor};
#[panic_handler] fn ph(_: &PanicInfo) -> ! { loop {} }

struct Sink { u: u64, i: i64 }
impl Visitor for Sink {
    fn unsigned(&mut self, _i: Id, v: Unsigned) { self.u = self.u.wrapping_add(v as u64); }
    fn signed(&mut self, _i: Id, v: Signed) { self.i = self.i.wrapping_add(v as i64); }
    fn fp32(&mut self, _i: Id, v: f32) { self.u = self.u.wrapping_add(v.to_bits() as u64); }
    fn fp64(&mut self, _i: Id, v: f64) { self.u = self.u.wrapping_add(v.to_bits()); }
    fn string(&mut self, _i: Id, t: usize, _o: usize, _c: &[u8]) { self.u = self.u.wrapping_add(t as u64); }
    fn blob(&mut self, _i: Id, t: usize, _o: usize, _c: &[u8]) { self.u = self.u.wrapping_add(t as u64); }
    fn array_begin(&mut self, _i: Id, _k: ArrayKind, c: usize) { self.u = self.u.wrapping_add(c as u64); }
    fn sequence_begin(&mut self, _i: Id) { self.u = self.u.wrapping_add(1); }
    fn sequence_end(&mut self) { self.u = self.u.wrapping_add(2); }
}

// Encode the full set of wire types the FullScaleExample schema uses.
#[no_mangle]
pub extern "C" fn sofab_enc(buf: *mut u8, len: usize, a: u64, b: i64) -> usize {
    let buf = unsafe { core::slice::from_raw_parts_mut(buf, len) };
    let mut os = OStream::new(buf);
    let _ = os.write_unsigned(1, a as Unsigned);
    let _ = os.write_signed(2, b as Signed);
    let _ = os.write_sequence_begin(10);
    let _ = os.write_fp32(0, f32::from_bits(a as u32));
    let _ = os.write_fp64(1, f64::from_bits(a));
    let _ = os.write_str(2, "Hello, World!");
    let _ = os.write_blob(3, &[1, 2, 3, 4]);
    let _ = os.write_sequence_end();
    let _ = os.write_sequence_begin(100);
    let _ = os.write_array_unsigned(0, &[a as u32, 1, 2, 3, 4]);
    let _ = os.write_array_signed(1, &[b as i32, -1, 2, -3, 4]);
    let _ = os.write_array_unsigned(6, &[a, 1, 2, 3, 4]);
    let _ = os.write_array_signed(7, &[b, -1, 2, -3, 4]);
    let _ = os.write_sequence_begin(10);
    let _ = os.write_array_fp32(0, &[f32::from_bits(a as u32), 1.0]);
    let _ = os.write_array_fp64(1, &[f64::from_bits(a), 1.0]);
    let _ = os.write_sequence_end();
    let _ = os.write_sequence_end();
    let _ = os.write_sequence_begin(200);
    let _ = os.write_str(0, "s");
    let _ = os.write_sequence_end();
    os.bytes_used()
}

#[no_mangle]
pub extern "C" fn sofab_dec(buf: *const u8, len: usize) -> u64 {
    let data = unsafe { core::slice::from_raw_parts(buf, len) };
    let mut s = Sink { u: 0, i: 0 };
    let mut is = IStream::new();
    let _ = is.feed(data, &mut s);
    s.u.wrapping_add(s.i as u64)
}
EOF
( cd "$SF" && cargo build --release --quiet )
emit sofab "$(sum_sections "$SF/target/release/libsofab_fp.a")"

# ---------------------------------------------------------------------------
# micropb: no_std staticlib including the real generated codec.
# ---------------------------------------------------------------------------
GEN_MSG="$(find "$HERE/micropb/target/release/build" -name message.rs -path '*out*' 2>/dev/null | head -1)"
if [ -z "$GEN_MSG" ]; then
    echo "footprint: generated micropb message.rs not found (run setup.sh first)" >&2
    emit micropb "0 0 0 0"
    exit 0
fi
MP="$WORK/micropb_fp"; mkdir -p "$MP/src"
cp "$GEN_MSG" "$MP/src/message.rs"
cat > "$MP/Cargo.toml" <<EOF
[package]
name = "micropb_fp"
version = "0.0.0"
edition = "2021"
[lib]
crate-type = ["staticlib"]
[dependencies]
micropb = { version = "0.6", default-features = false, features = ["encode", "decode", "container-heapless-0-8", "enable-64bit"] }
heapless = "0.8"
$PROFILE
EOF
cat > "$MP/src/lib.rs" <<'EOF'
#![no_std]
use core::panic::PanicInfo;
#[panic_handler] fn ph(_: &PanicInfo) -> ! { loop {} }

mod proto {
    #![allow(clippy::all, dead_code, non_snake_case, non_camel_case_types, unused)]
    include!("message.rs");
}
use micropb::{MessageDecode, MessageEncode, PbEncoder};
use proto::fullscale_::FullScaleExample;

#[no_mangle]
pub extern "C" fn micropb_enc(out: *mut u8, cap: usize) -> usize {
    let msg = FullScaleExample::default();
    let mut enc = PbEncoder::new(heapless::Vec::<u8, 1024>::new());
    let _ = msg.encode(&mut enc);
    let w = enc.into_writer();
    let n = core::cmp::min(w.len(), cap);
    unsafe { core::ptr::copy_nonoverlapping(w.as_ptr(), out, n); }
    n
}

#[no_mangle]
pub extern "C" fn micropb_dec(data: *const u8, len: usize) -> u64 {
    let slice = unsafe { core::slice::from_raw_parts(data, len) };
    let mut m = FullScaleExample::default();
    let _ = m.decode_from_bytes(slice);
    m.r#u64
}
EOF
( cd "$MP" && cargo build --release --quiet )
emit micropb "$(sum_sections "$MP/target/release/libmicropb_fp.a")"
