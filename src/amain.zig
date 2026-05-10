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

const Channel = struct {
    tfreq: f64, // really 2*pi*freq
    ratio: [3]f64,
    phase_off: [3]f64,
    attn: [3]f64,
};

fn make_noise(pcm: ?*c.snd_pcm_t, sample_rate: c_uint, period_size: usize) !void {
    var buffer: [MAX_FRAMES][2]i16 = undefined;
    const num_samples = 10 * sample_rate;
    const math = std.math;
    const FREQUENCY = 440.0;
    const DECREAS = 0.2;

    std.debug.print("sampel {} fast {}\n", .{ sample_rate, period_size });

    const one_over = 2 * math.pi / @as(f64, sample_rate);
    const seq_ticklen: u32 = @trunc(@as(f64, sample_rate) * 0.3);

    var ch: Channel = .{
        .tfreq = FREQUENCY * one_over,
        .ratio = .{ 3.0, 2.0, 1.0 },
        .phase_off = .{ 0, 0, 0 },
        .attn = .{ 0.1, 0.1, 0.2 },
    };

    var j: u32 = 0;
    var tick: u32 = 0;
    var seq_t: u32 = 0;
    for (0..num_samples) |i| {
        const t: f64 = @floatFromInt(i);

        var bus: f64 = 0;
        for (0..3) |k| {
            bus = ch.attn[k] + math.sin(ch.phase_off[k] + ch.ratio[k] * ch.tfreq * t + bus);
        }

        const sl = DECREAS * bus;
        const sr = DECREAS * bus;

        buffer[j][0] = @trunc((32767.0 * sl));
        buffer[j][1] = @trunc((32767.0 * sr));

        j += 1;
        if (j == period_size) {
            const res = c.snd_pcm_writei(pcm, @ptrCast(&buffer), 1 * period_size);
            if (res == -c.EPIPE) {
                std.debug.print("pipad:(\n", .{});
                try ok(c.snd_pcm_prepare(pcm));
            } else if (res < 0) {
                try ok(@intCast(res)); // NOT OK :(
            }
            j = 0;
        }

        seq_t += 1;
        if (seq_t >= seq_ticklen) {
            ch.ratio[1] = 5.0 - ch.ratio[1];

            tick += 1;
            seq_t = 0;
        }
    }
}

fn ok(status: c_int) !void {
    if (status < 0) {
        std.debug.print("foooka: {s}\n", .{c.snd_strerror(status)});
    }
}
