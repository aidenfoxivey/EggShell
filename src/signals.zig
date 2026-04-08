const std = @import("std");

var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
const stdout = &stdout_writer.interface;

const SignalHandler = struct {
    sig: u6,
    action: std.posix.Sigaction,
};

fn makeHandler(comptime f: fn (i32) callconv(.c) void, mask: std.posix.sigset_t) std.posix.Sigaction {
    return .{
        .handler = .{ .handler = f },
        .mask = mask,
        .flags = 0,
    };
}

fn makeIgnore(mask: std.posix.sigset_t) std.posix.Sigaction {
    return .{
        .handler = .{ .handler = std.posix.SIG.IGN },
        .mask = mask,
        .flags = 0,
    };
}

fn onSigint(_: i32) callconv(.c) void {
    stdout.print("\n\n$ ", .{}) catch {};
}
fn onSigterm(_: i32) callconv(.c) void {
    std.process.exit(0);
}

pub fn registerSignals() void {
    const mask = std.posix.sigemptyset();

    const signal_handlers = [_]SignalHandler{
        .{ .sig = std.posix.SIG.INT, .action = makeHandler(onSigint, mask) },
        .{ .sig = std.posix.SIG.TERM, .action = makeHandler(onSigterm, mask) },
        .{ .sig = std.posix.SIG.TSTP, .action = makeIgnore(mask) },
    };

    for (signal_handlers) |sh| {
        std.posix.sigaction(sh.sig, &sh.action, null);
    }
}
