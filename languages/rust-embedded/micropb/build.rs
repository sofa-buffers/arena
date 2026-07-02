// micropb codegen: compile schema/message.proto into a no_std, no-alloc Rust
// module backed by heapless fixed-capacity containers.
//
// Fixed sizes are configured per field to match the canonical message:
//   * str      -> heapless::String<32>
//   * bytes    -> heapless::Vec<u8, 4>
//   * repeated scalars / fp arrays -> heapless::Vec<T, 5>
//   * string_array -> heapless::Vec<heapless::String<64>, 5>
use micropb_gen::{Config, Generator};

fn main() {
    let manifest = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    // Local copy of schema/message.proto with explicit `[packed=true]` on the
    // repeated scalar/fp fields — required so micropb emits packed wire that
    // matches the protobuf baseline (see message.proto header for the why).
    let schema = manifest.clone();
    let proto = format!("{schema}/message.proto");
    let out = format!("{}/message.rs", std::env::var("OUT_DIR").unwrap());

    let mut gen = Generator::new();
    // Use heapless 0.8 containers (matches the `container-heapless-0-8` feature
    // and the `heapless = "0.8"` runtime dep).
    gen.use_container_heapless_v0_8();

    // --- FullScaleSeqStruct: scalar string + bytes ---
    gen.configure(
        ".fullscale.FullScaleSeqStruct.str",
        Config::new().max_bytes(32),
    );
    gen.configure(
        ".fullscale.FullScaleSeqStruct.bytes_field",
        Config::new().max_bytes(4),
    );

    // --- FullScaleSeqStructOfArrays: eight repeated scalar arrays (max 5) ---
    for f in ["u8", "i8", "u16", "i16", "u32", "i32", "u64", "i64"] {
        gen.configure(
            &format!(".fullscale.FullScaleSeqStructOfArrays.{f}"),
            Config::new().max_len(5),
        );
    }

    // --- FullScaleSeqStructOfFpArrays: repeated float/double (max 5) ---
    gen.configure(
        ".fullscale.FullScaleSeqStructOfFpArrays.fp32",
        Config::new().max_len(5),
    );
    gen.configure(
        ".fullscale.FullScaleSeqStructOfFpArrays.fp64",
        Config::new().max_len(5),
    );

    // --- FullScaleSeqArrayOfStrings: 5 strings, each up to 64 bytes ---
    gen.configure(
        ".fullscale.FullScaleSeqArrayOfStrings.strings",
        Config::new().max_len(5).max_bytes(64),
    );

    // Resolve the proto through an explicit proto_path so protoc can import it.
    gen.add_protoc_arg(format!("--proto_path={schema}"));
    gen.compile_protos(&[proto], out)
        .expect("micropb-gen: compile message.proto");

    println!("cargo:rerun-if-changed={schema}/message.proto");
}
