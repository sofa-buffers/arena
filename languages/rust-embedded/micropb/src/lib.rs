// Generated micropb message module, exported as a library so both the host
// bench binary (std) and the bare-metal footprint FFI wrapper (no_std) can use
// the identical codec. no_std under --no-default-features: micropb + heapless
// are both no-alloc; only the bench harness needs std.
#![cfg_attr(not(feature = "std"), no_std)]

pub mod proto {
    #![allow(clippy::all, dead_code, non_snake_case, non_camel_case_types, unused)]
    include!(concat!(env!("OUT_DIR"), "/message.rs"));
}
