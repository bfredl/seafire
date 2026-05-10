const std = @import("std");
const Io = std.Io;
const c = @import("asoundlib");

const MAX_FRAMES = 256;
pub fn main() !void {
    var pcm: ?*c.snd_pcm_t = undefined;
    const PCM_DEVICE = "default";

    try ok(c.snd_pcm_open(&pcm, PCM_DEVICE, c.SND_PCM_STREAM_PLAYBACK, 0));

    var params: ?*c.snd_pcm_hw_params_t = undefined;
    try ok(c.snd_pcm_hw_params_malloc(&params));
    try ok(c.snd_pcm_hw_params_any(pcm, params));

    var sample_rate: c_uint = 44100;

    var frames: c.snd_pcm_uframes_t = MAX_FRAMES; // Number of frames per period
    var period_size: c.snd_pcm_uframes_t = undefined;

    var dir: c_int = undefined;
    // Set parameters
    _ = c.snd_pcm_hw_params_set_access(pcm, params, c.SND_PCM_ACCESS_RW_INTERLEAVED);
    _ = c.snd_pcm_hw_params_set_format(pcm, params, c.SND_PCM_FORMAT_S16_LE);
    _ = c.snd_pcm_hw_params_set_channels(pcm, params, 2);
    _ = c.snd_pcm_hw_params_set_rate_near(pcm, params, &sample_rate, 0);
    _ = c.snd_pcm_hw_params_set_period_size_near(pcm, params, &frames, &dir);

    try ok(c.snd_pcm_hw_params(pcm, params));

    _ = c.snd_pcm_hw_params_get_period_size(params, &period_size, &dir);
    std.debug.print("afka {} but {}\n", .{ period_size, frames });

    try make_noise(pcm, sample_rate, period_size);

    // try ok(c.snd_pcm_prepare(pcm));

}

fn make_noise(pcm: ?*c.snd_pcm_t, sample_rate: c_uint, period_size: usize) !void {
    var buffer: [MAX_FRAMES][2]i16 = undefined;
    const num_samples = 10 * sample_rate;
    const math = std.math;
    const FREQUENCY = 440.0;
    const DECREAS = 0.2;
    for (0..(num_samples / period_size)) |i| {
        for (0..period_size) |j| {
            const t = @as(f64, @floatFromInt(i * period_size + j)) / sample_rate;
            const q0 = math.sin(4.001 * math.pi * FREQUENCY * t) * (t - @trunc(t)) * 0.2;
            const q = math.sin(5.001 * math.pi * FREQUENCY * t + q0) * (10 - t) * 0.2;
            buffer[j][0] = @trunc((32767.0 * DECREAS * 0.1 * (10 - t) * math.sin(2.0 * math.pi * FREQUENCY * t + q)));
            buffer[j][1] = @trunc((32767.0 * DECREAS * 0.1 * (10 - t) * math.sin(3.0 * math.pi * FREQUENCY * t + q)));
        }
        const res = c.snd_pcm_writei(pcm, @ptrCast(&buffer), period_size);
        if (res == -c.EPIPE) {
            std.debug.print("pipad:(\n", .{});
            try ok(c.snd_pcm_prepare(pcm));
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
