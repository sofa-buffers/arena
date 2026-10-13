// no_std FFI surface over the micropb-generated codec (heapless containers).
//
// The C footprint driver calls micropb_roundtrip(); everything the generated
// encode/decode reaches stays live under --gc-sections, so the link delta is
// the full codec surface. black_box keeps the decoded message observable.
#![no_std]

use micropb::{MessageDecode, MessageEncode, PbEncoder};
use micropb_msgs::proto::fullscale_::FullScaleExample;

/// Encode a (default-constructed) FullScaleExample into `buf`, decode it back;
/// returns the encoded length (0 on error). The values don't matter for
/// footprint — only the code paths reached by encode/decode do, and those are
/// value-independent.
///
/// # Safety
/// `buf` must point to at least `cap` writable bytes.
#[no_mangle]
pub unsafe extern "C" fn micropb_roundtrip(buf: *mut u8, cap: usize) -> usize {
    let out = core::slice::from_raw_parts_mut(buf, cap);
    // black_box: without it LTO const-folds the encode of a known-default
    // message (and transitively the decode), shrinking the delta to ~nothing.
    let msg = core::hint::black_box(FullScaleExample::default());
    // micropb's `&mut [u8]` writer: encode straight into the caller's buffer.
    let mut enc = PbEncoder::new(&mut *out);
    if msg.encode(&mut enc).is_err() {
        return 0;
    }
    let used = cap - enc.into_writer().len();
    let mut dec = FullScaleExample::default();
    if dec.decode_from_bytes(core::slice::from_raw_parts(buf, used)).is_err() {
        return 0;
    }
    core::hint::black_box(&dec);
    used
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
