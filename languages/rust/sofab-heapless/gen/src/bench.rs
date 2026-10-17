// SofaBuffers Rust benchmark target.
//
// Encodes + decodes the canonical FullScaleExample message (schema/state.json)
// through the sofabgen-generated `Example` type, which is backed by the real
// corelib-rs (std) runtime. Prints one uniform BENCH line (see docs/BENCH.md).
//
// Built as a second binary inside the generated crate (alongside `harness`),
// so it can `mod message;` and reuse the generated serialize/decode directly.
//
// ONE source, TWO builds (the Rust half of #107): setup.sh copies this file into
// both generated crates and builds them with identical RUSTFLAGS and profile,
// against the two corelib-rs storage profiles that sofabgen's `allow_dynamic`
// selects — growable (String/Vec) as impl=sofab and heap-free
// (heapless::String/heapless::Vec) as impl=sofab-heapless. Both profiles share
// one API and one wire, so the ONLY differences between the two runs are the
// generated `message` module and BENCH_IMPL below; sharing the source is what
// makes the pair a like-for-like measurement.
mod message;

/// Which storage profile this build measures; set by setup.sh (BENCH_IMPL env
/// var at compile time, the analogue of the C++ target's -DBENCH_IMPL).
const BENCH_IMPL: &str = match option_env!("BENCH_IMPL") {
    Some(s) => s,
    None => "sofab",
};

use message::Example;
use sofab::OStream;
use sha2::{Digest, Sha256};
use std::hint::black_box;

/// Process CPU time in seconds (docs/BENCH.md rule 3); same helper in every Rust driver.
fn cpu_seconds() -> f64 {
    let mut ts = libc::timespec { tv_sec: 0, tv_nsec: 0 };
    let rc = unsafe { libc::clock_gettime(libc::CLOCK_PROCESS_CPUTIME_ID, &mut ts) };
    assert_eq!(rc, 0, "clock_gettime(CLOCK_PROCESS_CPUTIME_ID)");
    ts.tv_sec as f64 + ts.tv_nsec as f64 * 1e-9
}

fn main() {
    // Build the message from the canonical jsonable state via serde (handles
    // u64::MAX etc., proven by conformance).
    let state_path = std::env::var("STATE_JSON").expect("STATE_JSON env var");
    let raw = std::fs::read(&state_path).expect("read STATE_JSON");
    let src: Example = serde_json::from_slice(&raw).expect("parse state.json into Example");

    // Warm-up round-trip + self-check (outside the timed region).
    let blob = src.encode().expect("sofab encode");
    let serialized = blob.len();
    // Byte-wise hex so it works across sha2 versions: 0.11's digest returns a
    // hybrid-array `Array` (no `LowerHex`), unlike 0.10's `GenericArray`.
    let sha: String = Sha256::digest(&blob).iter().map(|b| format!("{b:02x}")).collect();
    // try_decode: the whole-buffer decode that returns the verdict (prost's
    // decode is fallible too). It decodes INTO a destination we own and resets
    // that destination itself, so there is no fresh-message form to pick.
    let mut decoded = Example::default();
    Example::try_decode(&blob, &mut decoded).expect("sofab decode");
    if decoded.encode().expect("sofab re-encode") != blob {
        eprintln!("FAIL: sofab round-trip self-check");
        std::process::exit(1);
    }

    let iters: u64 = std::env::var("BENCH_ITERS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(2_000_000);

    // Reused encode buffer, hoisted out of the loop (docs/BENCH.md rule 3).
    let mut buf = vec![0u8; Example::MAX_SIZE];

    // Chained round trip: decode the reference wire, then re-encode the freshly
    // decoded message (issue #86) — the proxy/transcode shape, the same for both
    // impls.
    //
    // The destination is hoisted, because `try_decode(data, &mut out)` is now the
    // only verdict-surfacing decode the generated API offers: it writes into a
    // message the caller owns and resets that message itself, keeping the
    // storage its String/Vec fields already hold. Allocating a fresh `Example`
    // per iteration would hand that back and time the allocator instead of the
    // codec. docs/BENCH.md rule 6 therefore puts prost on the same footing: its
    // loop reuses one destination through `clear()` + `merge()`, prost's own
    // reset-then-decode pair, rather than `decode()`'s fresh message.
    let mut dec = Example::default();
    let mut used = 0usize;
    let t0 = cpu_seconds();
    for _ in 0..iters {
        Example::try_decode(&blob, &mut dec).expect("sofab decode");
        used = {
            let mut os = OStream::new(&mut buf);
            dec.serialize(&mut os).expect("sofab serialize");
            os.bytes_used()
        };
        black_box(&buf[..used]);
    }
    let cpu = cpu_seconds() - t0;

    if buf[..used] != blob[..] {
        eprintln!("FAIL: sofab loop-path self-check");
        std::process::exit(1);
    }

    let mbs = if cpu > 0.0 {
        (serialized as f64) * (iters as f64) / cpu / 1e6
    } else {
        0.0
    };
    // sizeof_bytes is the in-memory size of the message struct — the cost side of
    // the heap-free trade (#107): fixed-capacity storage sizes with the schema's
    // declared count/maxlen instead of with the payload, so it buys the decode
    // speed with RAM. Optional BENCH key; the runner reports it as a footnote.
    println!(
        "BENCH lang=rust impl={} serialized_bytes={} iters={} cpu_time_s={:.6} throughput_mbs={:.2} sizeof_bytes={} sha256={}",
        BENCH_IMPL, serialized, iters, cpu, mbs, std::mem::size_of::<Example>(), sha
    );
}
