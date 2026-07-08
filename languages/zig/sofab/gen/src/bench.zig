// SofaBuffers Zig benchmark target.
//
// Encodes + decodes the canonical FullScaleExample message (schema/STATE.md)
// through the sofabgen-generated `Example` type, backed by the real
// corelib-zig (max-speed) runtime. Prints one uniform BENCH line (docs/BENCH.md).
//
// Copied into the generated project (src/bench.zig) by languages/zig/setup.sh,
// so it can @import("message.zig") and reuse the generated marshal/decode
// directly — the same pattern as the Rust target's second crate binary.
//
// The message fill mirrors every other target in the arena — identical fields,
// ids and values as the .sofab / .proto definitions and the canonical state.
const std = @import("std");
const sofab = @import("sofab");
const message = @import("message.zig");

const Example = message.Example;

/// Process CPU time in seconds (not wall-clock), via
/// clock_gettime(CLOCK_PROCESS_CPUTIME_ID) — the contract's timing method
/// (docs/BENCH.md rule 3), same as the C/C++ targets.
fn cpuNow() f64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(.PROCESS_CPUTIME_ID, &ts);
    return @as(f64, @floatFromInt(ts.sec)) + @as(f64, @floatFromInt(ts.nsec)) / 1e9;
}

fn benchIters(init: std.process.Init, fallback: u64) u64 {
    const s = init.environ_map.get("BENCH_ITERS") orelse return fallback;
    const v = std.fmt.parseInt(u64, s, 10) catch return fallback;
    return if (v > 0) v else fallback;
}

/// The canonical field values from schema/STATE.md (machine: state.json).
fn fill() Example {
    return .{
        .u8 = 200,
        .i8 = -100,
        .u16 = 50000,
        .i16 = -20000,
        .u32 = 3000000000,
        .i32 = -1000000000,
        .u64 = 10000000000000,
        .i64 = -5000000000000,
        .nested = .{
            .f32 = 3.14,
            .f64 = 3.14159265,
            .str = "Hello, World!",
            .bytes_field = &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF },
        },
        .arrays = .{
            .u8 = .{ 0, 64, 128, 191, 255 },
            .i8 = .{ -128, -64, 0, 63, 127 },
            .u16 = .{ 0, 16384, 32768, 49151, 65535 },
            .i16 = .{ -32768, -16384, 0, 16383, 32767 },
            .u32 = .{ 0, 1073741824, 2147483648, 3221225471, 4294967295 },
            .i32 = .{ -2147483648, -1073741824, 0, 1073741823, 2147483647 },
            .u64 = .{ 0, 4611686018427387904, 9223372036854775808, 13835058055282163711, 18446744073709551615 },
            .i64 = .{ -9223372036854775807, -4611686018427387904, 0, 4611686018427387903, 9223372036854775807 },
            .nested = .{
                .fp32 = .{ 1.0, 2.0, 3.0, -std.math.floatMax(f32), std.math.floatMax(f32) },
                .fp64 = .{ 1.0, 2.0, 3.0, -std.math.floatMax(f64), std.math.floatMax(f64) },
            },
        },
        .string_array = &.{
            "Hello, Sofab!",
            "",
            "1234567890",
            "äöüÄÖÜß",
            "This_is_a_very_long_test_string_with_!@#$%^&*()_+-=[]{}",
        },
    };
}

pub fn main(init: std.process.Init) !void {
    const src = fill();

    // Warm-up round-trip + self-check (outside the timed region).
    var buf: [Example.MAX_SIZE]u8 = undefined;
    var os = sofab.OStream.init(&buf);
    try src.marshal(&os);
    const serialized = os.bytesUsed();
    const wire = buf[0..serialized];

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(wire, &digest, .{});

    // decode() borrows string/blob bytes from `wire` and takes array storage
    // from the allocator — a fixed stack buffer keeps the whole codec heap-free.
    var dec_mem: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&dec_mem);

    // Round-trip is correct iff the decoded message re-encodes to the same bytes.
    const check = try Example.decode(fba.allocator(), wire);
    var check_buf: [Example.MAX_SIZE]u8 = undefined;
    var check_os = sofab.OStream.init(&check_buf);
    try check.marshal(&check_os);
    if (!std.mem.eql(u8, check_buf[0..check_os.bytesUsed()], wire)) {
        std.debug.print("FAIL: sofab round-trip self-check\n", .{});
        std.process.exit(1);
    }

    // Timed loop: ONLY encode + decode (buffers hoisted; the fixed decode
    // arena is rewound per iteration, which frees the whole message at once).
    const iters = benchIters(init, 2_000_000);
    var loop_buf: [Example.MAX_SIZE]u8 = undefined;
    var dec: Example = .{};
    const t0 = cpuNow();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        var eos = sofab.OStream.init(&loop_buf);
        try src.marshal(&eos);
        const used = eos.bytesUsed();
        fba.reset();
        dec = try Example.decode(fba.allocator(), loop_buf[0..used]);
        std.mem.doNotOptimizeAway(&dec);
    }
    const cpu = cpuNow() - t0;

    var loop_check_os = sofab.OStream.init(&check_buf);
    try dec.marshal(&loop_check_os);
    if (!std.mem.eql(u8, check_buf[0..loop_check_os.bytesUsed()], wire)) {
        std.debug.print("FAIL: sofab loop-path self-check\n", .{});
        std.process.exit(1);
    }

    const mbs = if (cpu > 0.0)
        @as(f64, @floatFromInt(serialized)) * @as(f64, @floatFromInt(iters)) / cpu / 1e6
    else
        0.0;

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const out = &stdout_writer.interface;
    try out.print(
        "BENCH lang=zig impl=sofab serialized_bytes={d} iters={d} cpu_time_s={d:.6} throughput_mbs={d:.2} sha256={x}\n",
        .{ serialized, iters, cpu, mbs, digest[0..] },
    );
    try out.flush();
}
