// Protobuf Zig baseline build: zig-protobuf runtime + its protoc codegen step.
//
//   zig build gen-proto       regenerate src/gen/fullscale.pb.zig from
//                             schema/message.proto (protoc-gen-zig; protoc is a
//                             lazy dependency of zig-protobuf — nothing global)
//   zig build --release=fast  build the bench binary (same optimize mode as the
//                             sofab side, so the row compares like with like)
const std = @import("std");
const protobuf = @import("protobuf");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const protobuf_dep = b.dependency("protobuf", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/bench.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("protobuf", protobuf_dep.module("protobuf"));
    b.installArtifact(b.addExecutable(.{ .name = "bench", .root_module = mod }));

    const gen_proto = b.step("gen-proto", "generate zig sources from schema/message.proto");
    const protoc_step = protobuf.RunProtocStep.create(protobuf_dep.builder, target, .{
        .destination_directory = b.path("src/gen"),
        .source_files = &.{b.path("../../../schema/message.proto")},
        .include_directories = &.{b.path("../../../schema")},
    });
    gen_proto.dependOn(&protoc_step.step);
}
