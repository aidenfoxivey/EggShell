const std = @import("std");


var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
const stdout = &stdout_writer.interface;

var stdin_buffer: [4096]u8 = undefined;
var stdin_reader = std.fs.File.stdin().readerStreaming(&stdin_buffer);
const stdin = &stdin_reader.interface;

const Command = struct {
    command: []const u8,
    args: [][]const u8,
};

const CommandType = enum {
    exit,
    echo,
    type,
    unknown,
};

fn parseCommand(allocator: std.mem.Allocator) !Command {
    const fullCommand = try stdin.takeDelimiter('\n');
    var it = std.mem.splitSequence(u8, fullCommand.?, " ");

    const command = it.next().?;

    var args_list: std.ArrayList([]const u8) = .empty;
    defer args_list.deinit(allocator);

    while (it.next()) |arg| {
        try args_list.append(allocator, arg);
    }

    return Command{
        .command = command,
        .args = try args_list.toOwnedSlice(allocator),
    };
}


fn commandType(cmd: []const u8) CommandType {
    if (std.mem.eql(u8, cmd, "exit")) return .exit;
    if (std.mem.eql(u8, cmd, "echo")) return .echo;
    if (std.mem.eql(u8, cmd, "type")) return .type;
    return .unknown;
}

fn checkPath(allocator: std.mem.Allocator, query: []const u8) ![][]const u8 {
    const env_map = try allocator.create(std.process.EnvMap);
    env_map.* = try std.process.getEnvMap(allocator);

    const path = env_map.get("PATH") orelse "";
    var dirs = std.mem.splitSequence(u8, path, ":");


    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(allocator);
    
    while (dirs.next()) |dir| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ dir, query });

        if (std.fs.accessAbsolute(full_path, .{})) {
            try paths.append(allocator, full_path);
        } else |_| {}
    }

    return paths.toOwnedSlice(allocator);
}

pub fn main() !void {           
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit(); 

    const allocator = arena.allocator();


    while (true) {
        try stdout.print("$ ", .{});
        const command = try parseCommand(allocator);

        switch (commandType(command.command)) {
            .exit => std.process.exit(0),
            .echo => {
                const args = try std.mem.join(allocator, " ", command.args);
                try stdout.print("{s}\n", .{args});
            },
            .type => {
                const arg = command.args[0];
                if (command.args.len > 0 and commandType(arg) != .unknown) {
                    try stdout.print("{s} is a shell builtin\n", .{arg});
                    continue;
                }

                const paths = try checkPath(allocator, arg);

                if (paths.len == 0) {
                    try stdout.print("{s}: not found\n", .{arg}); 
                } else {
                    for (paths) |path| {
                        try stdout.print("{s} is {s}\n", .{arg, path});
                    }
                }
            },
            .unknown => {
                try stdout.print("{s}: command not found\n", .{command.command});
            },
        }

    }
}
