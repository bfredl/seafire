const std = @import("std");
const Io = std.Io;
const c = @import("asoundlib");

pub fn main() !void {
    var pcm_handle: ?*c.snd_pcm_t = undefined;
    const PCM_DEVICE = "default";

    try ok(c.snd_pcm_open(&pcm_handle, PCM_DEVICE, c.SND_PCM_STREAM_PLAYBACK, 0));

    var params: ?*c.snd_pcm_hw_params_t = undefined;
    try ok(c.snd_pcm_hw_params_malloc(&params));
    try ok(c.snd_pcm_hw_params_any(pcm_handle, params));

    var sample_rate: c_uint = 44100;
    const MAX_FRAMES = 32;

    var frames: c.snd_pcm_uframes_t = MAX_FRAMES; // Number of frames per period
    var period_size: c.snd_pcm_uframes_t = undefined;

    var dir: c_int = undefined;
    // Set parameters
    _ = c.snd_pcm_hw_params_set_access(pcm_handle, params, c.SND_PCM_ACCESS_RW_INTERLEAVED);
    _ = c.snd_pcm_hw_params_set_format(pcm_handle, params, c.SND_PCM_FORMAT_S16_LE);
    _ = c.snd_pcm_hw_params_set_channels(pcm_handle, params, 2);
    _ = c.snd_pcm_hw_params_set_rate_near(pcm_handle, params, &sample_rate, 0);
    _ = c.snd_pcm_hw_params_set_period_size_near(pcm_handle, params, &frames, &dir);

    try ok(c.snd_pcm_hw_params(pcm_handle, params));

    _ = c.snd_pcm_hw_params_get_period_size(params, &period_size, &dir);
    std.debug.print("afka {} but {}\n", .{ period_size, frames });

    var buffer: [MAX_FRAMES][2]i16 = undefined;

    // try ok(c.snd_pcm_prepare(pcm_handle));

    const num_samples = 10 * sample_rate;
    const math = std.math;
    const FREQUENCY = 440.0;
    for (0..(num_samples / period_size)) |i| {
        for (0..period_size) |j| {
            const t = @as(f64, @floatFromInt(i * period_size + j)) / sample_rate;
            const q = math.sin(5.0 * math.pi * FREQUENCY * t) * t;
            buffer[j][0] = @trunc((32767.0 * math.sin(2.0 * math.pi * FREQUENCY * t + q)));
            buffer[j][1] = @trunc((32767.0 * math.sin(3.0 * math.pi * FREQUENCY * t + q)));
        }
        const res = c.snd_pcm_writei(pcm_handle, @ptrCast(&buffer), period_size);
        if (res == -c.EPIPE) {
            std.debug.print("pipad:(\n", .{});
            try ok(c.snd_pcm_prepare(pcm_handle));
        } else if (res < 0) {
            try ok(@intCast(res)); // NOT OK :(
        }
    }
}

fn ok(status: c_int) !void {
    if (status < 0) {
        std.debug.print("foooka: {s}\n", .{c.snd_strerror(status)});
    }
}
