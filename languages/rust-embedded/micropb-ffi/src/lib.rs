// no_std FFI surface over the micropb-generated codec (heapless containers).
//
// The C footprint driver calls micropb_roundtrip(); everything the generated
// encode/decode reaches stays live under --gc-sections, so the link delta is
// the full codec surface. black_box keeps the decoded message observable.
#![no_std]

use micropb::{MessageDecode, MessageEncode, PbEncoder};
use micropb_msgs::proto::fullscale_::FullScaleExample;

// Encode buffer capacity — matches the host bench (message is ~494 B).
const CAP: usize = 1024;

/// Encode a (default-constructed) FullScaleExample, decode it back, copy the
/// wire into `out`; returns the encoded length (0 on error). Values don't
/// matter for footprint — only the code paths reached, which are
/// value-independent.
///
/// # Safety
/// `out` must point to at least `cap` writable bytes.
#[no_mangle]
pub unsafe extern "C" fn micropb_roundtrip(out: *mut u8, cap: usize) -> usize {
    // black_box: without it LTO const-folds the encode of a known-default
    // message (and transitively the decode), shrinking the delta to ~nothing.
    let msg = core::hint::black_box(FullScaleExample::default());
    let mut enc = PbEncoder::new(heapless::Vec::<u8, CAP>::new());
    if msg.encode(&mut enc).is_err() {
        return 0;
    }
    let blob = enc.into_writer();
    let mut dec = FullScaleExample::default();
    if dec.decode_from_bytes(&blob[..]).is_err() {
        return 0;
    }
    core::hint::black_box(&dec);
    let n = if blob.len() <= cap { blob.len() } else { cap };
    core::ptr::copy_nonoverlapping(blob.as_ptr(), out, n);
    n
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
