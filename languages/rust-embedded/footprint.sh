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
# Both impls are measured the SAME way: the .a holds the real generated codec for
# that schema plus its runtime, exercised through the entry points a firmware
# user calls.
#   * micropb  — micropb-gen output + micropb runtime + heapless, via
#                encode/decode_from_bytes of the real message.
#   * sofab    — the sofabgen-generated message crate (corelib: rs-no-std) built
#                --no-default-features, i.e. the genuinely #![no_std], heap-free
#                lib (heapless fields, no serde), plus corelib-rs-no-std, via
#                encode/try_decode of the real message.
#
# This used to be asymmetric: sofab was measured through a hand-written no_std
# harness of raw OStream/IStream calls, because the generated crate "carries
# serde/Vec/String (std) and cannot be compiled no_std as-is". That stopped being
# true — sofabgen's rs-no-std profile emits a feature-gated lib whose default
# features are the only std part, which is exactly how languages/rust-embedded/
# sofab-ffi links the same generated codec for the bare-metal siblings. Measuring
# a stand-in left the generated glue (field dispatch, visitor, bound checks) out
# of sofab's number while micropb's was counted in full.
#
# CAVEAT (provisional): the fair metric is a bare-metal ARM --gc-sections build —
# that is what languages/rust-cortex-m / rust-riscv do with the same crates.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

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
# sofab: no_std staticlib over the GENERATED codec (the real message crate).
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
# The generated crate, built as the heap-free #![no_std] lib (its "std" default
# feature is what pulls serde/serde_json); it brings corelib-rs-no-std and
# heapless with it, the same way sofab-ffi/Cargo.toml links it for the
# bare-metal siblings.
msgs = { package = "sofabuffers-generated", path = "$HERE/sofab/gen", default-features = false }
$PROFILE
EOF
cat > "$SF/src/lib.rs" <<'EOF'
#![no_std]
use core::panic::PanicInfo;
#[panic_handler] fn ph(_: &PanicInfo) -> ! { loop {} }

use msgs::Example;

// Same two entry points, same shape, as the micropb half below: encode a
// default-constructed message into a fixed-capacity buffer, decode a buffer back
// into a message. Values do not matter for footprint, only the code paths
// reached -- and those are value-independent.
#[no_mangle]
pub extern "C" fn sofab_enc(out: *mut u8, cap: usize) -> usize {
    let msg = Example::default();
    // encode() returns heapless::Vec<u8, MAX_SIZE> in this profile: fixed
    // capacity, nothing on the heap.
    let w = match msg.encode() { Ok(w) => w, Err(_) => return 0 };
    let n = core::cmp::min(w.len(), cap);
    unsafe { core::ptr::copy_nonoverlapping(w.as_ptr(), out, n); }
    n
}

#[no_mangle]
pub extern "C" fn sofab_dec(data: *const u8, len: usize) -> u64 {
    let slice = unsafe { core::slice::from_raw_parts(data, len) };
    // try_decode, not decode: the fallible whole-buffer form, so the verdict
    // code counts -- micropb's only decode form is fallible too.
    match Example::try_decode(slice) { Ok(m) => m.u64, Err(_) => 0 }
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
