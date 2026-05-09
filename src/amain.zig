const std = @import("std");
const Io = std.Io;
const c = @cImport({
    @cInclude("alsa/asoundlib.h");
});

pub fn main() !void {
    var pcm_handle: ?*c.snd_pcm_t = undefined;
    const PCM_DEVICE = "default";

    const res = c.snd_pcm_open(&pcm_handle, PCM_DEVICE, c.SND_PCM_STREAM_PLAYBACK, 0);
    std.debug.print("aaa {}\n", .{res});
}
