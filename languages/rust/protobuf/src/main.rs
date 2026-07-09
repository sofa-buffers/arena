// Protobuf Rust benchmark target (prost).
//
// Encodes + decodes the SAME FullScaleExample message with the SAME canonical
// values (schema/STATE.md), hand-filled. Same timed region + method as the
// SofaBuffers target. Prints one uniform BENCH line (see docs/BENCH.md).
pub mod fullscale {
    include!(concat!(env!("OUT_DIR"), "/fullscale.rs"));
}

use fullscale::*;
use prost::Message;
use sha2::{Digest, Sha256};
use std::hint::black_box;
use std::time::Instant;

fn build() -> FullScaleExample {
    FullScaleExample {
        u8: 200,
        i8: -100,
        u16: 50000,
        i16: -20000,
        u32: 3000000000,
        i32: -1000000000,
        u64: 10000000000000,
        i64: -5000000000000,
        nested: Some(FullScaleSeqStruct {
            f32: 3.14,
            f64: 3.14159265,
            str: "Hello, World!".to_string(),
            bytes_field: vec![0xDE, 0xAD, 0xBE, 0xEF],
        }),
        arrays: Some(FullScaleSeqStructOfArrays {
            u8: vec![0, 64, 128, 191, 255],
            i8: vec![-128, -64, 0, 63, 127],
            u16: vec![0, 16384, 32768, 49151, 65535],
            i16: vec![-32768, -16384, 0, 16383, 32767],
            u32: vec![0, 1073741824, 2147483648, 3221225471, 4294967295],
            i32: vec![-2147483648, -1073741824, 0, 1073741823, 2147483647],
            u64: vec![
                0,
                4611686018427387904,
                9223372036854775808,
                13835058055282163711,
                18446744073709551615,
            ],
            i64: vec![
                -9223372036854775807,
                -4611686018427387904,
                0,
                4611686018427387903,
                9223372036854775807,
            ],
            nested: Some(FullScaleSeqStructOfFpArrays {
                fp32: vec![1.0, 2.0, 3.0, -3.4028234663852886e38, 3.4028234663852886e38],
                fp64: vec![
                    1.0,
                    2.0,
                    3.0,
                    -1.7976931348623157e308,
                    1.7976931348623157e308,
                ],
            }),
        }),
        string_array: Some(FullScaleSeqArrayOfStrings {
            strings: vec![
                "Hello, Sofab!".to_string(),
                "".to_string(),
                "1234567890".to_string(),
                "äöüÄÖÜß".to_string(),
                "This_is_a_very_long_test_string_with_!@#$%^&*()_+-=[]{}".to_string(),
            ],
        }),
    }
}

fn main() {
    let src = build();

    // Warm-up round-trip + self-check (outside the timed region).
    let mut blob = Vec::with_capacity(src.encoded_len());
    src.encode(&mut blob).unwrap();
    let serialized = blob.len();
    // Byte-wise hex so it works across sha2 versions: 0.11's digest returns a
    // hybrid-array `Array` (no `LowerHex`), unlike 0.10's `GenericArray`.
    let sha: String = Sha256::digest(&blob).iter().map(|b| format!("{b:02x}")).collect();
    let decoded = FullScaleExample::decode(&blob[..]).expect("decode");
    let mut re = Vec::new();
    decoded.encode(&mut re).unwrap();
    if re != blob {
        eprintln!("FAIL: protobuf round-trip self-check");
        std::process::exit(1);
    }

    let iters: u64 = std::env::var("BENCH_ITERS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(2_000_000);

    let mut buf = Vec::with_capacity(serialized);

    let t0 = Instant::now();
    for _ in 0..iters {
        buf.clear();
        src.encode(&mut buf).unwrap();
        let dec = FullScaleExample::decode(&buf[..]).unwrap();
        black_box(&dec);
    }
    let cpu = t0.elapsed().as_secs_f64();

    let mbs = if cpu > 0.0 {
        (serialized as f64) * (iters as f64) / cpu / 1e6
    } else {
        0.0
    };
    println!(
        "BENCH lang=rust impl=protobuf serialized_bytes={} iters={} cpu_time_s={:.6} throughput_mbs={:.2} sha256={}",
        serialized, iters, cpu, mbs, sha
    );
}
