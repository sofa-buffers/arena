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

fn benchEnvU64(init: std.process.Init, key: []const u8, fallback: u64) u64 {
    const s = init.environ_map.get(key) orelse return fallback;
    const v = std.fmt.parseInt(u64, s, 10) catch return fallback;
    return if (v > 0) v else fallback;
}

fn benchIters(init: std.process.Init, fallback: u64) u64 {
    return benchEnvU64(init, "BENCH_ITERS", fallback);
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

/// Streaming encode (#108), the opponent of sofab-stream: zig-protobuf encodes
/// into a `std.Io.Writer`, so a Writer whose buffer is SMALLER than the message
/// and whose drain hands the bytes on is protobuf's own bounded-buffer encode —
/// the same question sofab-stream asks, answered with this library's own
/// abstraction rather than a harness invention.
const Sink = struct {
    var buf: [2048]u8 = undefined;
    var n: usize = 0;

    fn push(data: []const u8) void {
        @memcpy(buf[n..][0..data.len], data);
        n += data.len;
    }

    /// Flush the Writer's own buffer, then consume every incoming vector.
    /// `splat` repeats the last vector, per the std.Io.Writer contract.
    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        push(w.buffer[0..w.end]);
        w.end = 0;
        var consumed: usize = 0;
        if (data.len == 0) return 0;
        for (data[0 .. data.len - 1]) |d| {
            push(d);
            consumed += d.len;
        }
        const last = data[data.len - 1];
        var k: usize = 0;
        while (k < splat) : (k += 1) {
            push(last);
            consumed += last.len;
        }
        return consumed;
    }

    const vtable: std.Io.Writer.VTable = .{ .drain = drain };
};

fn streamEncode(m: pb.FullScaleExample, scratch: []u8, alloc: std.mem.Allocator) !usize {
    Sink.n = 0;
    var w: std.Io.Writer = .{ .vtable = &Sink.vtable, .buffer = scratch, .end = 0 };
    try m.encode(&w, alloc);
    try w.flush();   // hand over the tail still sitting in the buffer
    return Sink.n;
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

    const impl = init.environ_map.get("BENCH_IMPL") orelse "protobuf";
    const streaming = std.mem.eql(u8, impl, "protobuf-stream");
    const stream_cap = benchEnvU64(init, "STREAM_BUF_BYTES", 64);
    var stream_scratch: [512]u8 = undefined;
    const scratch = stream_scratch[0..@min(stream_cap, stream_scratch.len)];

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
        const ok = if (streaming) blk: {
            const n = try streamEncode(check, scratch, arena.allocator());
            break :blk n == serialized and std.mem.eql(u8, Sink.buf[0..n], wire);
        } else blk: {
            var cw = std.Io.Writer.fixed(&check_buf);
            try check.encode(&cw, arena.allocator());
            break :blk std.mem.eql(u8, cw.buffered(), wire);
        };
        if (!ok) {
            std.debug.print("FAIL: protobuf round-trip self-check\n", .{});
            std.process.exit(1);
        }
    }

    // Timed loop: chained round trip — decode the reference wire, then re-encode
    // the freshly decoded message (issue #86) — the proxy/transcode shape, so
    // encode runs on a just-parsed message rather than a pre-built, reused one.
    // Output buffer hoisted; the arena is rewound per iteration, keeping its pages.
    //
    // Two loops, picked before t0, so neither impl pays a per-iteration branch the
    // other does not. Only the ENCODE half differs — the decode stays the plain
    // one-shot parse in both.
    const iters = benchIters(init, 2_000_000);
    var loop_buf: [2048]u8 = undefined;
    var loop_wire: []const u8 = &.{};
    var dec: pb.FullScaleExample = .{};
    var cpu: f64 = 0;
    if (streaming) {
        const t0 = cpuNow();
        var i: u64 = 0;
        while (i < iters) : (i += 1) {
            _ = arena.reset(.retain_capacity);
            var r = std.Io.Reader.fixed(wire);
            dec = try pb.FullScaleExample.decode(&r, arena.allocator());
            const n = try streamEncode(dec, scratch, arena.allocator());
            std.mem.doNotOptimizeAway(Sink.buf[0..n]);
        }
        cpu = cpuNow() - t0;
    } else {
        const t0 = cpuNow();
        var i: u64 = 0;
        while (i < iters) : (i += 1) {
            _ = arena.reset(.retain_capacity);
            var r = std.Io.Reader.fixed(wire);
            dec = try pb.FullScaleExample.decode(&r, arena.allocator());
            var ew = std.Io.Writer.fixed(&loop_buf);
            try dec.encode(&ew, arena.allocator());
            loop_wire = ew.buffered();
            std.mem.doNotOptimizeAway(loop_wire);
        }
        cpu = cpuNow() - t0;
    }

    const loop_ok = if (streaming) blk: {
        const n = try streamEncode(dec, scratch, arena.allocator());
        break :blk n == serialized and std.mem.eql(u8, Sink.buf[0..n], wire);
    } else blk: {
        var cw = std.Io.Writer.fixed(&check_buf);
        try dec.encode(&cw, arena.allocator());
        break :blk std.mem.eql(u8, cw.buffered(), wire);
    };
    if (!loop_ok) {
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
        "BENCH lang=zig impl={s} serialized_bytes={d} iters={d} cpu_time_s={d:.6} throughput_mbs={d:.2} sha256={x}\n",
        .{ impl, serialized, iters, cpu, mbs, digest[0..] },
    );
    try out.flush();
}
