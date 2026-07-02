// SofaBuffers Rust *embedded* benchmark target (no_std corelib).
//
// Encodes + decodes the canonical FullScaleExample message (schema/state.json)
// through the sofabgen-generated `Example` type, which here is backed by the
// no_std corelib (vendor/corelib-rs-no-std). The host bench binary itself uses
// std (serde_json, timing); only the codec crate is the no_std corelib. Prints
// one uniform BENCH line (see docs/BENCH.md).
//
// Built as a second binary inside the generated crate (alongside `harness`),
// so it can `mod message;` and reuse the generated marshal/decode directly.
mod message;

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
    let sha = format!("{:x}", Sha256::digest(&blob));
    let decoded = Example::decode(&blob);
    if decoded.encode() != blob {
        eprintln!("FAIL: sofab round-trip self-check");
        std::process::exit(1);
    }

    let iters: u64 = std::env::var("BENCH_ITERS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(500_000);

    // Reused encode buffer (decode allocates its own object internally).
    let mut buf = vec![0u8; Example::MAX_SIZE];

    let t0 = Instant::now();
    for _ in 0..iters {
        let used = {
            let mut os = OStream::new(&mut buf);
            src.marshal(&mut os);
            os.bytes_used()
        };
        let dec = Example::decode(&buf[..used]);
        black_box(&dec);
    }
    let cpu = t0.elapsed().as_secs_f64();

    let mbs = if cpu > 0.0 {
        (serialized as f64) * (iters as f64) / cpu / 1e6
    } else {
        0.0
    };
    println!(
        "BENCH lang=rust-embedded impl=sofab serialized_bytes={} iters={} cpu_time_s={:.6} throughput_mbs={:.2} sha256={}",
        serialized, iters, cpu, mbs, sha
    );
}
