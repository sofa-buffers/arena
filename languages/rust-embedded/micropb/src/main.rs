// micropb (no_std, no-alloc) benchmark target — embedded category.
//
// Encodes + decodes the SAME FullScaleExample message with the SAME canonical
// values (schema/state.json), built with fixed-capacity heapless containers.
// Same timed region + method as the SofaBuffers embedded target. Prints one
// uniform BENCH line (see docs/BENCH.md). The message wire is proto3 (packed
// repeated scalars), byte-identical to the protobuf baseline.
//
// The harness itself uses std (timing/hash/env); the codec crate (micropb +
// the generated module) is no_std, no-alloc.
use micropb::{MessageDecode, MessageEncode, PbEncoder};
use micropb_msgs::proto;
use proto::fullscale_::{
    FullScaleExample, FullScaleSeqArrayOfStrings, FullScaleSeqStruct, FullScaleSeqStructOfArrays,
    FullScaleSeqStructOfFpArrays,
};
use sha2::{Digest, Sha256};
use std::hint::black_box;
use std::time::Instant;

// Encode buffer capacity (message is ~494 B; give generous headroom).
const CAP: usize = 1024;

fn hs<const N: usize>(s: &str) -> heapless::String<N> {
    let mut out = heapless::String::<N>::new();
    out.push_str(s).expect("string fits capacity");
    out
}

fn vec5<T: Copy, const N: usize>(xs: &[T]) -> heapless::Vec<T, N> {
    heapless::Vec::from_slice(xs).expect("slice fits capacity")
}

fn build() -> FullScaleExample {
    let mut msg = FullScaleExample::default();
    msg.r#u8 = 200;
    msg.r#i8 = -100;
    msg.r#u16 = 50000;
    msg.r#i16 = -20000;
    msg.r#u32 = 3000000000;
    msg.r#i32 = -1000000000;
    msg.r#u64 = 10000000000000;
    msg.r#i64 = -5000000000000;

    let mut nested = FullScaleSeqStruct::default();
    nested.r#f32 = 3.14;
    nested.r#f64 = 3.14159265;
    nested.r#str = hs::<32>("Hello, World!");
    nested.r#bytes_field = vec5::<u8, 4>(&[0xDE, 0xAD, 0xBE, 0xEF]);
    msg.set_nested(nested);

    let mut arrays = FullScaleSeqStructOfArrays::default();
    arrays.r#u8 = vec5::<u32, 5>(&[0, 64, 128, 191, 255]);
    arrays.r#i8 = vec5::<i32, 5>(&[-128, -64, 0, 63, 127]);
    arrays.r#u16 = vec5::<u32, 5>(&[0, 16384, 32768, 49151, 65535]);
    arrays.r#i16 = vec5::<i32, 5>(&[-32768, -16384, 0, 16383, 32767]);
    arrays.r#u32 = vec5::<u32, 5>(&[0, 1073741824, 2147483648, 3221225471, 4294967295]);
    arrays.r#i32 = vec5::<i32, 5>(&[-2147483648, -1073741824, 0, 1073741823, 2147483647]);
    arrays.r#u64 = vec5::<u64, 5>(&[
        0,
        4611686018427387904,
        9223372036854775808,
        13835058055282163711,
        18446744073709551615,
    ]);
    arrays.r#i64 = vec5::<i64, 5>(&[
        -9223372036854775807,
        -4611686018427387904,
        0,
        4611686018427387903,
        9223372036854775807,
    ]);
    let mut fp = FullScaleSeqStructOfFpArrays::default();
    fp.r#fp32 = vec5::<f32, 5>(&[1.0, 2.0, 3.0, -f32::MAX, f32::MAX]);
    fp.r#fp64 = vec5::<f64, 5>(&[1.0, 2.0, 3.0, -f64::MAX, f64::MAX]);
    arrays.set_nested(fp);
    msg.set_arrays(arrays);

    let mut sa = FullScaleSeqArrayOfStrings::default();
    sa.r#strings = {
        let mut v = heapless::Vec::<heapless::String<64>, 5>::new();
        v.push(hs::<64>("Hello, Sofab!")).unwrap();
        v.push(hs::<64>("")).unwrap();
        v.push(hs::<64>("1234567890")).unwrap();
        v.push(hs::<64>("äöüÄÖÜß")).unwrap();
        v.push(hs::<64>("This_is_a_very_long_test_string_with_!@#$%^&*()_+-=[]{}"))
            .unwrap();
        v
    };
    msg.set_string_array(sa);

    msg
}

fn encode(msg: &FullScaleExample) -> heapless::Vec<u8, CAP> {
    let mut enc = PbEncoder::new(heapless::Vec::<u8, CAP>::new());
    msg.encode(&mut enc).expect("micropb encode");
    enc.into_writer()
}

fn main() {
    let src = build();

    // Warm-up round-trip + self-check (outside the timed region).
    let blob = encode(&src);
    let serialized = blob.len();
    let sha = format!("{:x}", Sha256::digest(&blob[..]));

    let mut decoded = FullScaleExample::default();
    decoded
        .decode_from_bytes(&blob[..])
        .expect("micropb decode");
    let re = encode(&decoded);
    if re != blob {
        eprintln!("FAIL: micropb round-trip self-check");
        std::process::exit(1);
    }

    let iters: u64 = std::env::var("BENCH_ITERS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(500_000);

    let t0 = Instant::now();
    for _ in 0..iters {
        let b = encode(&src);
        let mut d = FullScaleExample::default();
        d.decode_from_bytes(&b[..]).unwrap();
        black_box(&d);
    }
    let cpu = t0.elapsed().as_secs_f64();

    let mbs = if cpu > 0.0 {
        (serialized as f64) * (iters as f64) / cpu / 1e6
    } else {
        0.0
    };
    println!(
        "BENCH lang=rust-embedded impl=micropb serialized_bytes={} iters={} cpu_time_s={:.6} throughput_mbs={:.2} sha256={}",
        serialized, iters, cpu, mbs, sha
    );
}
