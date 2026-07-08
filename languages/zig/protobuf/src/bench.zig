// Protobuf Zig benchmark target (zig-protobuf).
//
// Encodes + decodes the SAME FullScaleExample message with the SAME canonical
// values (schema/STATE.md), hand-filled. Same timed region + method as the
// SofaBuffers target. Prints one uniform BENCH line (see docs/BENCH.md).
const std = @import("std");
const pb = @import("gen/fullscale.pb.zig");

/// Process CPU time in seconds (not wall-clock), via
/// clock_gettime(CLOCK_PROCESS_CPUTIME_ID) — identical to the sofab side.
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
/// `alloc` owns the repeated-field storage for the message's whole lifetime.
fn fill(alloc: std.mem.Allocator) !pb.FullScaleExample {
    var arrays: pb.FullScaleSeqStructOfArrays = .{};
    try arrays.u8.appendSlice(alloc, &.{ 0, 64, 128, 191, 255 });
    try arrays.i8.appendSlice(alloc, &.{ -128, -64, 0, 63, 127 });
    try arrays.u16.appendSlice(alloc, &.{ 0, 16384, 32768, 49151, 65535 });
    try arrays.i16.appendSlice(alloc, &.{ -32768, -16384, 0, 16383, 32767 });
    try arrays.u32.appendSlice(alloc, &.{ 0, 1073741824, 2147483648, 3221225471, 4294967295 });
    try arrays.i32.appendSlice(alloc, &.{ -2147483648, -1073741824, 0, 1073741823, 2147483647 });
    try arrays.u64.appendSlice(alloc, &.{ 0, 4611686018427387904, 9223372036854775808, 13835058055282163711, 18446744073709551615 });
    try arrays.i64.appendSlice(alloc, &.{ -9223372036854775807, -4611686018427387904, 0, 4611686018427387903, 9223372036854775807 });

    var fp: pb.FullScaleSeqStructOfFpArrays = .{};
    try fp.fp32.appendSlice(alloc, &.{ 1.0, 2.0, 3.0, -std.math.floatMax(f32), std.math.floatMax(f32) });
    try fp.fp64.appendSlice(alloc, &.{ 1.0, 2.0, 3.0, -std.math.floatMax(f64), std.math.floatMax(f64) });
    arrays.nested = fp;

    var strings: pb.FullScaleSeqArrayOfStrings = .{};
    try strings.strings.appendSlice(alloc, &.{
        "Hello, Sofab!",
        "",
        "1234567890",
        "äöüÄÖÜß",
        "This_is_a_very_long_test_string_with_!@#$%^&*()_+-=[]{}",
    });

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
        .arrays = arrays,
        .string_array = strings,
    };
}

pub fn main(init: std.process.Init) !void {
    // The source message lives in its own arena, never reset; the encode
    // scratch + decode output use a second arena rewound per iteration (the
    // zig-protobuf recommended pattern — it frees each message at once).
    var fill_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer fill_arena.deinit();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const src = try fill(fill_arena.allocator());

    // Warm-up round-trip + self-check (outside the timed region).
    var buf: [2048]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try src.encode(&w, arena.allocator());
    const wire = w.buffered();
    const serialized = wire.len;

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(wire, &digest, .{});

    // Round-trip is correct iff the decoded message re-encodes to the same bytes.
    var check_buf: [2048]u8 = undefined;
    {
        var r = std.Io.Reader.fixed(wire);
        const check = try pb.FullScaleExample.decode(&r, arena.allocator());
        var cw = std.Io.Writer.fixed(&check_buf);
        try check.encode(&cw, arena.allocator());
        if (!std.mem.eql(u8, cw.buffered(), wire)) {
            std.debug.print("FAIL: protobuf round-trip self-check\n", .{});
            std.process.exit(1);
        }
    }

    // Timed loop: ONLY encode + decode (output buffer hoisted; the arena is
    // rewound per iteration, keeping its pages).
    const iters = benchIters(init, 2_000_000);
    var loop_buf: [2048]u8 = undefined;
    var loop_wire: []const u8 = &.{};
    var dec: pb.FullScaleExample = .{};
    const t0 = cpuNow();
    var i: u64 = 0;
    while (i < iters) : (i += 1) {
        _ = arena.reset(.retain_capacity);
        var ew = std.Io.Writer.fixed(&loop_buf);
        try src.encode(&ew, arena.allocator());
        loop_wire = ew.buffered();
        var r = std.Io.Reader.fixed(loop_wire);
        dec = try pb.FullScaleExample.decode(&r, arena.allocator());
        std.mem.doNotOptimizeAway(&dec);
    }
    const cpu = cpuNow() - t0;

    var cw = std.Io.Writer.fixed(&check_buf);
    try dec.encode(&cw, arena.allocator());
    if (!std.mem.eql(u8, cw.buffered(), wire)) {
        std.debug.print("FAIL: protobuf loop-path self-check\n", .{});
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
        "BENCH lang=zig impl=protobuf serialized_bytes={d} iters={d} cpu_time_s={d:.6} throughput_mbs={d:.2} sha256={x}\n",
        .{ serialized, iters, cpu, mbs, digest[0..] },
    );
    try out.flush();
}
