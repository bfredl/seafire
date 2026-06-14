const std = @import("std");
const Io = std.Io;
const c = @import("asoundlib");

const MAX_FRAMES = 256;
pub fn main(init: std.process.Init) !void {
    var pcm: ?*c.snd_pcm_t = undefined;
    const PCM_DEVICE = "default";

    const argv = init.minimal.args.vector;
    if (argv.len < 2) return error.usage;
    const firstarg = std.mem.span(argv[1]);
    const readin = try readall(init.io, init.gpa, firstarg);

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

    try make_noise(pcm, sample_rate, period_size, readin);

    // try ok(c.snd_pcm_prepare(pcm));

}

const Channel = struct {
    tfreq: f64, // really 2*pi*freq
    ratio: [3]f64,
    phase_off: [3]f64,
    attn: [3]f64,
};

const BASE_FREQUENCY = 440.0;
const math = std.math;
const pi = math.pi;

ch: [4]Channel = @splat(.{
    .tfreq = 0,
    .ratio = .{ 3.0, 2.0, 1.0 },
    .phase_off = .{ 0, 0, 0 },
    .attn = .{ 1.3, 0.9, 0.0 },
}),
pat_pos: usize = 0,
pattern: []u8,
one_over: f64,

fn render(ch: *Channel) f64 {
    var bus: f64 = 0;
    for (0..3) |k| {
        ch.phase_off[k] += ch.ratio[k] * ch.tfreq;
        bus = ch.attn[k] * std.math.sin(ch.phase_off[k] + bus);
        if (ch.phase_off[k] > 2 * pi) {
            ch.phase_off[k] -= 2 * pi;
        }
    }
    return bus;
}

fn make_noise(pcm: ?*c.snd_pcm_t, sample_rate: c_uint, period_size: usize, pattern: []u8) !void {
    var buffer: [MAX_FRAMES][2]i16 = undefined;
    const num_samples = 200 * sample_rate;
    const DECREAS = 0.2;

    std.debug.print("sampel {} fast {}\n", .{ sample_rate, period_size });

    const seq_ticklen: u32 = @trunc(@as(f64, sample_rate) * 0.3);

    var self: @This() = .{ .pattern = pattern, .one_over = 2 * pi / @as(f64, sample_rate) };
    var seq_t: u32 = 0;

    var j: u32 = 0;
    // var tick: u32 = 0;
    for (0..num_samples) |_| {
        var sl: f64 = 0;
        var sr: f64 = 0;

        for (&self.ch) |*ch| {
            const sig = render(ch);
            sl += DECREAS * sig;
            sr += DECREAS * sig;
        }

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
            self.seqtick();
            seq_t = 0;
        }
    }
}

pub fn seqtick(self: *@This()) void {
    //tick += 1;
    const p = self.pattern;
    var pos = self.pat_pos;
    var octave: u32 = 0;

    var ch = &self.ch[0];
    var chix: u32 = 0;

    while (true) {
        while (pos < p.len) : (pos += 1) {
            if (p[pos] != ' ') {
                break;
            }
        }
        if (pos == p.len) {
            pos = 0;
            break;
        }
        const cmd = p[pos];
        pos += 1;
        if (cmd == '\n') {
            if (pos == p.len)
                pos = 0;
            break;
        }

        if (cmd == ',') {
            chix += 1;
            if (chix >= self.ch.len) @panic("at the bar");
            ch = &self.ch[chix];
        } else if (cmd == 'n' or cmd == 'N') {
            const oct = octave + if (cmd == 'n') @as(u32, 1) else 0;
            const n = @as(u32, @intCast(num(p, &pos))) + 31 * oct;
            const freq = 220.0 * std.math.pow(f64, 2, n / @as(f64, 31.0));
            ch.tfreq = freq * self.one_over;
        } else if (note(cmd, p, &pos)) |n| {
            const freq = 220.0 * std.math.pow(f64, 2, (n - 2 * 31 - 23) / @as(f64, 31.0));
            ch.tfreq = freq * self.one_over;
        } else if (cmd == 'v') {
            const n: u32 = @intCast(num(p, &pos));
            ch.attn[2] = n / @as(f64, 100.0);
        } else if (cmd == 'r') {
            for (0..2) |i| {
                const k = p[pos];
                if ('0' <= k and k <= '9') {
                    ch.ratio[i] = k - '0';
                    pos += 1;
                } else break;
            }
        } else if (cmd == 'o') {
            octave = @intCast(num(p, &pos));
        }
    }
    self.pat_pos = pos;
    // ch.ratio[1] = 5.0 - ch.ratio[1];

}

pub fn num(p: []u8, pos: *usize) u64 {
    var val: u64 = 0;
    while (pos.* < p.len) : (pos.* += 1) {
        const next = p[pos.*];
        if ('0' <= next and next <= '9') {
            val = val * 10 + (next - '0');
        } else {
            break;
        }
    }
    return val;
}

pub fn note(sym: u8, p: []u8, pos: *usize) ?i32 {
    const symval: i32 = switch (sym) {
        'c', 'C' => 0,
        'd', 'D' => 5,
        'e', 'E' => 10,
        'f', 'F' => 13,
        'g', 'G' => 18,
        'a', 'A' => 23,
        'b', 'B' => 28,
        else => return null,
    };

    if (pos.* + 2 > p.len) @panic("haha");
    const sign = p[pos.*];
    const oct = p[pos.* + 1];
    pos.* += 2;

    const signval: i32 = switch (sign) {
        'b' => -2,
        '<' => -1,
        '-' => 0,
        '|' => 1,
        '#' => 2,
        else => @panic("y"),
    };

    if (!('0' <= oct and oct <= '9')) @panic("aaaa");
    const octval = (oct - '0') * 31;

    return symval + signval + octval;
}

fn ok(status: c_int) !void {
    if (status < 0) {
        std.debug.print("foooka: {s}\n", .{c.snd_strerror(status)});
    }
}

pub fn readall(io: std.Io, gpa: std.mem.Allocator, filename: []const u8) ![]u8 {
    const fil = try std.Io.Dir.cwd().openFile(io, filename, .{});
    const stat = try fil.stat(io);
    const size = std.math.cast(usize, stat.size) orelse return error.FileTooBig;
    const buf = try gpa.alloc(u8, size);
    if (try fil.readStreaming(io, &.{buf}) < size) {
        return error.IOError;
    }
    return buf;
}
