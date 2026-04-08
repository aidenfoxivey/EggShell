const std = @import("std");
const signals = @import("signals.zig");
const parser = @import("parser.zig");

var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
const stdout = &stdout_writer.interface;

var stdin_buffer: [4096]u8 = undefined;
var stdin_reader = std.fs.File.stdin().readerStreaming(&stdin_buffer);
const stdin = &stdin_reader.interface;

const CommandType = enum {
    exit,
    echo,
    type,
    cd,
    unknown,
};

fn commandType(cmd: []const u8) CommandType {
    if (std.mem.eql(u8, cmd, "exit")) return .exit;
    if (std.mem.eql(u8, cmd, "echo")) return .echo;
    if (std.mem.eql(u8, cmd, "type")) return .type;
    if (std.mem.eql(u8, cmd, "cd")) return .cd;
    return .unknown;
}

// for a command check if it exists in path
fn findMatchingPath(allocator: std.mem.Allocator, paths: [][]const u8, command: []const u8) !?[]const u8 {
    for (paths) |path| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, command });
        if (std.fs.accessAbsolute(full_path, .{})) {
            return full_path;
        } else |_| {}
    }
    return null;
}

// Execute an arbritary command in the current terminal window (ex: pwd,..)
fn execute(command: []const []const u8, allocator: std.mem.Allocator) !u8 {
    var child = std.process.Child.init(command, allocator);

    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    child.spawn() catch {
        std.debug.print("command not found: {s}\n", .{command[0]});
        return 127;
    };

    return switch (try child.wait()) {
        .Exited => |code| code,
        .Signal => |sig| blk: {
            std.debug.print("killed by signal {d}\n", .{sig});
            break :blk 1;
        },
        .Stopped => 1,
        .Unknown => 1,
    };
}

pub fn main() !void {
    signals.registerSignals();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const path_env = env_map.get("PATH") orelse "";
    var it = std.mem.splitSequence(u8, path_env, ":");

    const home_env = env_map.get("HOME") orelse "";

    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(allocator);

    while (it.next()) |p| {
        const copy = try allocator.dupe(u8, p);
        try paths.append(allocator, copy);
    }

    while (true) {
        try stdout.print("$ ", .{});
        const input = try stdin.takeDelimiter('\n') orelse {
            try stdout.print("\n", .{});
            std.process.exit(0);
        };
        const commands = try parser.parseCommands(input, allocator);
        for (commands) | command | {
            switch (commandType(command[0])) {
                .exit => std.process.exit(0),
                .echo => {
                    const args = try std.mem.join(allocator, " ", command[1..]);
                    try stdout.print("{s}\n", .{args});
                },
                .type => {
                    const arg = command[1];
                    if (commandType(arg) != .unknown) {
                        try stdout.print("{s} is a shell builtin\n", .{arg});
                        continue;
                    }

                    if (try findMatchingPath(allocator, paths.items, arg)) |match| {
                        try stdout.print("{s} is {s}\n", .{ arg, match });
                    } else {
                        try stdout.print("{s}: not found\n", .{arg});
                    }
                },
                .cd => {
                    var path = home_env;

                    if (command.len > 1) {
                        path = command[1];
                    }

                    if (std.mem.eql(u8, path, "~")) {
                        path = home_env;
                    }

                    if (std.fs.cwd().openDir(path, .{})) |d| {
                        var dir = d;
                        defer dir.close();
                        try dir.setAsCwd();
                    } else |_| {
                        try stdout.print("{s}: No such file or directory\n", .{command[1]});
                    }
                },
                .unknown => {
                    if (try findMatchingPath(allocator, paths.items, command[0])) |_| {
                        const response = try execute(command, allocator);
                        if (response != 0) {
                            try stdout.print("{s}: failed with status code {d}\n", .{ command[0], response });
                        }
                    } else {
                        try stdout.print("{s}: command not found\n", .{command[0]});
                    }
                },
            }
        }
    }
}
