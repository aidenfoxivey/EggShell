const std = @import("std");

const Token = union(enum) {
    word: []const u8,
    // TODO: implement features as needed
    // pipe, // |
    // logical_and, // &&
};

pub const Command = [][]const u8;
const Commands = []Command;

fn isSpecialCharacter(c: u8) bool {
    return switch (c) {
        ' ', '\n', '"', '|' => true,
        else => false,
    };
}
fn tokenize(input: []const u8, allocator: std.mem.Allocator) ![]Token {
    var tokens: std.ArrayList(Token) = .empty;

    var i: usize = 0;
    while (i < input.len) {
        switch (input[i]) {
            ' ', '\n' => i += 1,
            '"' => {
                const start = i + 1;
                i += 1;
                while (i < input.len and input[i] != '"') : (i += 1) {}
                const str = input[start..i];
                try tokens.append(allocator, .{ .word = str });
                i += 1;
            },
            else => {
                const start = i;
                while (i < input.len and !isSpecialCharacter(input[i])) : (i += 1) {}
                try tokens.append(allocator, .{ .word = input[start..i] });
            },
        }
    }

    return tokens.toOwnedSlice(allocator);
}

fn parse(tokens: []Token, allocator: std.mem.Allocator) !Commands {
    var commands: std.ArrayList(Command) = .empty;
    var current: std.ArrayList([]const u8) = .empty;

    for (tokens) |t| {
        switch (t) {
            .word => |w| try current.append(allocator, w),
        }
    }

    // last command
    if (current.items.len > 0) {
        try commands.append(allocator, try current.toOwnedSlice(allocator));
    }

    return try commands.toOwnedSlice(allocator);
}

pub fn parseCommands(input: []const u8, allocator: std.mem.Allocator) !Commands {
    const tokens = try tokenize(input, allocator);
    const commands = try parse(tokens, allocator);

    return commands;
}
