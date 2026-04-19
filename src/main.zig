const std = @import("std");
const Io = std.Io;
const c = @cImport({
    @cInclude("portaudio.h");
});
const seafire = @import("seafire");

fn callback(
    input: ?*const anyopaque,
    output: ?*anyopaque,
    frames_per_buffer: c_ulong,
    time_info: [*c]const c.PaStreamCallbackTimeInfo,
    flags: c.PaStreamCallbackFlags,
    ctx: ?*anyopaque,
) callconv(.c) c_int {
    _ = input;
    _ = time_info;
    _ = flags;
    const output_ptr: [*]f32 = @ptrCast(@alignCast(output.?));

    const len: usize = @intCast(frames_per_buffer);
    _ = len;
    _ = output_ptr;
    _ = ctx;
    const ret = .more;

    return switch (ret) {
        .complete => c.paComplete,
        .more => c.paContinue,
        .abort => c.paAbort,
        else => unreachable,
    };
}

pub fn handleError(err: c_int) !void {
    std.debug.print("hååå: {}\n", .{err});
}

pub fn main(init: std.process.Init) !void {
    // Prints to stderr, unbuffered, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    const status = c.Pa_Initialize();
    std.debug.print("faaka: {}\n", .{status});
    const arena: std.mem.Allocator = init.arena.allocator();

    // const buffer = try arena.alloc(f32, 8192);

    var stream: *c.PaStream = undefined;

    var state: struct {} = .{};

    const mono = true;
    const sample_rate = 44100;
    const frames_per_buffer = 1028;
    const ret = c.Pa_OpenDefaultStream(
        @ptrCast(&stream),
        @intCast(2),
        @intFromBool(mono),
        c.paFloat32,
        sample_rate,
        @intCast(frames_per_buffer),
        callback,
        @ptrCast(&state),
    );
    try handleError(ret);
    try handleError(c.Pa_StartStream(stream));

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);
    for (args) |arg| {
        std.log.info("arg: {s}", .{arg});
    }

    // In order to do I/O operations need an `Io` instance.
    const io = init.io;

    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try stdout_writer.flush(); // Don't forget to flush!
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
