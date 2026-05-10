const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("seafire", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const portaudio = b.dependency("portaudio", .{
        .target = target,
        .optimize = optimize,
    });

    const Translator = @import("translate_c").Translator;

    // You *can* pass `target` and/or `optimize` in the options struct here, but it's typically
    // not necessary. You usually want to build for the host target, which is the default.
    const translate_c = b.dependency("translate_c", .{});

    const t: Translator = .init(translate_c, .{
        .c_source_file = b.path("src/alsa_inc.h"),
        .target = target,
        .optimize = optimize,
        // more options go here (see below)
    });
    // If you want, you can now call methods on `Translator` to add include paths (etc).

    const exe = b.addExecutable(.{
        .name = "old_seafire",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "seafire", .module = mod },
            },
        }),
    });

    const thelib = portaudio.artifact("portaudio");
    exe.root_module.linkLibrary(thelib);
    // b.installArtifact(exe);

    const aexe = b.addExecutable(.{
        .name = "seafire",
        .use_lld = true,
        .use_llvm = true,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/amain.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "seafire", .module = mod },
                .{ .name = "asoundlib", .module = t.mod },
            },
        }),
    });
    aexe.root_module.linkSystemLibrary("asound", .{});
    b.installArtifact(aexe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(aexe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
