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
use std::time::Instant;

fn main() {
    // Build the message from the canonical jsonable state via serde (handles
    // u64::MAX etc., proven by conformance).
    let state_path = std::env::var("STATE_JSON").expect("STATE_JSON env var");
    let raw = std::fs::read(&state_path).expect("read STATE_JSON");
    let src: Example = serde_json::from_slice(&raw).expect("parse state.json into Example");

    // Warm-up round-trip + self-check (outside the timed region).
    let blob = src.encode();
    let serialized = blob.len();
    // Byte-wise hex so it works across sha2 versions: 0.11's digest returns a
    // hybrid-array `Array` (no `LowerHex`), unlike 0.10's `GenericArray`.
    let sha: String = Sha256::digest(&blob).iter().map(|b| format!("{b:02x}")).collect();
    let decoded = Example::decode(&blob);
    if decoded.encode() != blob {
        eprintln!("FAIL: sofab round-trip self-check");
        std::process::exit(1);
    }

    let iters: u64 = std::env::var("BENCH_ITERS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(2_000_000);

    // Reused encode buffer (decode allocates its own object internally).
    let mut buf = vec![0u8; Example::MAX_SIZE];

    // Chained round trip: decode the reference wire, then re-encode the freshly
    // decoded message (issue #86) — the proxy/transcode shape, which denies
    // protobuf its once-per-instance serialized-size memo so encode is measured
    // on equal terms.
    let t0 = Instant::now();
    for _ in 0..iters {
        let dec = Example::decode(&blob);
        let used = {
            let mut os = OStream::new(&mut buf);
            dec.serialize(&mut os);
            os.bytes_used()
        };
        black_box(&buf[..used]);
    }
    let cpu = t0.elapsed().as_secs_f64();

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
