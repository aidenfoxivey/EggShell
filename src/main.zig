const std = @import("std");

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

fn parseCommand(allocator: std.mem.Allocator) ![]const[]const u8 {
    const fullCommand = try stdin.takeDelimiter('\n');
    var it = std.mem.splitSequence(u8, fullCommand.?, " ");

    var command: std.ArrayList([]const u8) = .empty;

    while (it.next()) |arg| {
        try command.append(allocator, arg);
    }
    
    return command.toOwnedSlice(allocator);
}

fn commandType(cmd: []const u8) CommandType {
    if (std.mem.eql(u8, cmd, "exit")) return .exit;
    if (std.mem.eql(u8, cmd, "echo")) return .echo;
    if (std.mem.eql(u8, cmd, "type")) return .type;
    if (std.mem.eql(u8, cmd, "cd")) return .cd; 
    return .unknown;
}

// given a command check if we can find a matching absolute path for
// it inside a list of paths
fn findMatchingPath(allocator: std.mem.Allocator, paths: [][]const u8, command: []const u8) ![][]const u8 {
    var matches: std.ArrayList([]const u8) = .empty;

    for (paths) |path| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, command });

        if (std.fs.accessAbsolute(full_path, .{})) {
            try matches.append(allocator, full_path);
        } else |_| {}
    }
    
    return matches.toOwnedSlice(allocator);
}


// Execute an arbritary command in the current terminal window (ex: pwd,..) 
fn execute(command: []const []const u8, allocator: std.mem.Allocator) !u8 {
    var child = std.process.Child.init(command, allocator);

    child.stdin_behavior  = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    child.spawn() catch {
        std.debug.print("command not found: {s}\n", .{command[0]});
        return 127;
    };

    return switch (try child.wait()) {
        .Exited  => |code| code,
        .Signal  => |sig|  blk: { 
            std.debug.print("killed by signal {d}\n", .{sig});
            break :blk 1;
        },
        .Stopped => 1,
        .Unknown => 1,
    };
}

pub fn main() !void {
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
        const command = try parseCommand(allocator);
        if (command.len == 1 ) {
            try stdout.print("character: {d}\n", .{command[0]});
            continue;
        }

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
                const matches = try findMatchingPath(allocator, paths.items, arg);

                if (matches.len == 0) {
                    try stdout.print("{s}: not found\n", .{arg});
                } else {
                    for (matches) |match| {
                        try stdout.print("{s} is {s}\n", .{ arg, match });
                    }
                }

            },
            .cd => { 
                var path = home_env;

                if (command.len > 2) {
                    path = command[1];
                }

                var dir = try std.fs.cwd().openDir(path, .{});
                defer dir.close();

                try dir.setAsCwd();
            }, 
            .unknown => {
                const matches = try findMatchingPath(allocator, paths.items, command[0]);

                if (matches.len == 0) {
                    try stdout.print("{s}: not found\n", .{command[0]});
                } else {
                    const response = try execute(command, allocator);
                    if (response != 0) {
                        try stdout.print("{s}: failed with status code {d}\n", .{command[0], response});
                    }
                }

            },
        }
    }
}
