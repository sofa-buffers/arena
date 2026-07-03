// no_std FFI surface over the sofabgen-generated codec (corelib-rs-no-std).
//
// The C footprint driver calls sofab_roundtrip(); everything the generated
// marshal/decode reaches stays live under --gc-sections, so the link delta is
// the full codec surface. black_box keeps the decoded message observable.
#![no_std]

use msgs::Example;
use sofab::OStream;

/// Encode a (default-constructed) Example into `buf`, decode it back; returns
/// the encoded length. The values don't matter for footprint — only the code
/// paths reached by marshal/decode do, and those are value-independent.
///
/// # Safety
/// `buf` must point to at least `cap` writable bytes.
#[no_mangle]
pub unsafe extern "C" fn sofab_roundtrip(buf: *mut u8, cap: usize) -> usize {
    let out = core::slice::from_raw_parts_mut(buf, cap);
    // black_box: without it LTO const-folds the encode of a known-default
    // message (and transitively the decode), shrinking the delta to ~nothing.
    let msg = core::hint::black_box(Example::default());
    let mut os = OStream::new(out);
    msg.marshal(&mut os);
    let used = os.bytes_used();
    let dec = Example::decode(core::slice::from_raw_parts(buf, used));
    core::hint::black_box(&dec);
    used
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
