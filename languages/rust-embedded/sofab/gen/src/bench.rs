// SofaBuffers Rust *embedded* benchmark target (no_std corelib).
//
// Encodes + decodes the canonical FullScaleExample message (schema/state.json)
// through the sofabgen-generated `Example` type, which here is backed by the
// no_std corelib (vendor/corelib-rs-no-std). The host bench binary itself uses
// std (serde_json, timing); only the codec crate is the no_std corelib. Prints
// one uniform BENCH line (see docs/BENCH.md).
//
// Built as a second binary inside the generated crate (alongside `harness`),
// so it can `mod message;` and reuse the generated serialize/decode directly.
mod message;

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
    // try_decode: the whole-buffer decode that returns the verdict (micropb's
    // decode_from_bytes is fallible too).
    let decoded = Example::try_decode(&blob).expect("sofab decode");
    if decoded.encode().expect("sofab re-encode") != blob {
        eprintln!("FAIL: sofab round-trip self-check");
        std::process::exit(1);
    }

    let iters: u64 = std::env::var("BENCH_ITERS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(500_000);

    // Reused encode buffer, hoisted out of the loop (docs/BENCH.md rule 3).
    let mut buf = vec![0u8; Example::MAX_SIZE];

    // Chained round trip: decode the reference wire, then re-encode the freshly
    // decoded message (issue #86) -- the proxy/transcode shape docs/BENCH.md
    // rule 3 prescribes. try_decode returns a fresh message each iteration, as
    // the micropb driver decodes into a fresh default.
    let mut used = 0usize;
    let t0 = cpu_seconds();
    for _ in 0..iters {
        let dec = Example::try_decode(&blob).expect("sofab decode");
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
    println!(
        "BENCH lang=rust-embedded impl=sofab serialized_bytes={} iters={} cpu_time_s={:.6} throughput_mbs={:.2} sha256={}",
        serialized, iters, cpu, mbs, sha
    );
}
