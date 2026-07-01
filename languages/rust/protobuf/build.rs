fn main() {
    // Compile the shared schema with the installed protoc (via prost-build).
    let proto = "../../../schema/message.proto";
    prost_build::compile_protos(&[proto], &["../../../schema"]).unwrap();
    println!("cargo:rerun-if-changed={}", proto);
}
