const std = @import("std");
const signals = @import("signals.zig");
const parser = @import("parser.zig");
const builtins = @import("builtins.zig");
const Command = parser.Command;

var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
const stdout = &stdout_writer.interface;

var stdin_buffer: [4096]u8 = undefined;
var stdin_reader = std.fs.File.stdin().readerStreaming(&stdin_buffer);
const stdin = &stdin_reader.interface;

pub fn main() !void {
    signals.registerSignals();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    while (true) {
        try stdout.print("$ ", .{});
        const input = try stdin.takeDelimiter('\n') orelse {
            try stdout.print("\n", .{});
            std.process.exit(0);
        };
        const commands = try parser.parseCommands(input, allocator);
        for (commands) |command| {
            try switch (builtins.parseBuiltin(command)) {
                .exit => builtins.doExit(command, allocator),
                .echo => builtins.doEcho(command, allocator),
                .type => builtins.doType(command, allocator),
                .pwd => builtins.doPwd(command, allocator),
                .cd => builtins.doCd(command, allocator),
                .unknown => builtins.doUnknown(command, allocator),
            };
        }
    }
}
