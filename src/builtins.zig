const std = @import("std");
const parser = @import("parser.zig");
const Command = parser.Command;

const Builtin = enum {
    exit,
    echo,
    type,
    cd,
    pwd,
    unknown,
};

pub fn parseBuiltin(command: Command) Builtin {
    const cmd = command[0];
    if (std.mem.eql(u8, cmd, "exit")) return .exit;
    if (std.mem.eql(u8, cmd, "pwd")) return .pwd;
    if (std.mem.eql(u8, cmd, "cd")) return .cd;
    if (std.mem.eql(u8, cmd, "echo")) return .echo;
    if (std.mem.eql(u8, cmd, "type")) return .type;
    return .unknown;
}

var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
const stdout = &stdout_writer.interface;

pub fn doExit(_: Command, _: std.mem.Allocator) noreturn {
    std.process.exit(0);
}

pub fn doEcho(command: Command, allocator: std.mem.Allocator) !void {
    const args = try std.mem.join(allocator, " ", command[1..]);
    try stdout.print("{s}\n", .{args});
}

pub fn doType(command: Command, allocator: std.mem.Allocator) !void {
    // TODO: bring this functionality back
    const arg = command[1];
    // if (parseBuiltin(arg) != .unknown) {
    //     try stdout.print("{s} is a shell builtin\n", .{arg});
    //     return;
    // }

    if (try findMatchingPath(allocator, arg)) |match| {
        try stdout.print("{s} is {s}\n", .{ arg, match });
    } else {
        try stdout.print("{s}: not found\n", .{arg});
    }
}

pub fn doPwd(_: Command, allocator: std.mem.Allocator) !void {
    const path = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(path);
    try stdout.print("{s}\n", .{path});
}

pub fn doCd(command: Command, allocator: std.mem.Allocator) !void {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const home_env = env_map.get("HOME") orelse "";
    var path = home_env;

    if (command.len > 1) {
        path = command[1];
    }

    if (std.mem.eql(u8, path, "~")) {
        path = home_env;
    }

    // This hadnles relative paths like ".."
    if (std.fs.cwd().openDir(path, .{})) |d| {
        var dir = d;
        defer dir.close();
        try dir.setAsCwd();
    } else |_| {
        try stdout.print("{s}: No such file or directory\n", .{command[1]});
    }
}

pub fn doUnknown(command: Command, allocator: std.mem.Allocator) !void {
    if (try findMatchingPath(allocator, command[0])) |_| {
        const response = try execute(command, allocator);
        if (response != 0) {
            try stdout.print("{s}: failed with status code {d}\n", .{ command[0], response });
        }
    } else {
        try stdout.print("{s}: command not found\n", .{command[0]});
    }
}


// for a command check if it exists in path
fn findMatchingPath(allocator: std.mem.Allocator, command: []const u8) !?[]const u8 {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const path_env = env_map.get("PATH") orelse "";

    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(allocator);

    var it = std.mem.splitSequence(u8, path_env, ":");
    while (it.next()) |p| {
        const copy = try allocator.dupe(u8, p);
        try paths.append(allocator, copy);
    }

    for (paths.items) |path| {
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

