const std = @import("std");
const testing = std.testing;

const Token = union(enum) {
    word: []const u8,
    // TODO: implement features as needed
    pipe, // |
    logical_or, // ||
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
            '|' => {
                if (i + 1 < input.len and input[i + 1] == '|') {
                    try tokens.append(allocator, Token.logical_or);
                    i += 2;
                } else {
                    try tokens.append(allocator, Token.pipe);
                    i += 1;
                }
            },
            '&' => {
                if (i + 1 < input.len and input[i + 1] == '&') {
                    try tokens.append(allocator, .{ .word = "&&" });
                    i += 2;
                } else {
                    try tokens.append(allocator, .{ .word = "&" });
                    i += 1;
                }
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

fn expectTokens(input: []const u8, expected: []const Token, allocator: std.mem.Allocator) !void {
    const tokens = try tokenize(input, allocator);
    defer allocator.free(tokens);
    try testing.expectEqualDeep(expected, tokens);
}

test "canonical example" {
    try expectTokens("echo hello world", &[_]Token{ Token{ .word = "echo" }, Token{ .word = "hello" }, Token{ .word = "world" } }, testing.allocator);
}

test "quotes" {
    try expectTokens("echo \"hello world\"", &[_]Token{ Token{ .word = "echo" }, Token{ .word = "hello world" } }, testing.allocator);
}

// TODO: Decide if an unmatched quote should be an error or if it should just assume until \n is the quote.
test "unmatched quote" {
    try expectTokens("echo \"hello world", &[_]Token{ Token{ .word = "echo" }, Token{ .word = "hello world" } }, testing.allocator);
}

test "leading and trailing spaces" {
    try expectTokens("   echo hello world   ", &[_]Token{ Token{ .word = "echo" }, Token{ .word = "hello" }, Token{ .word = "world" } }, testing.allocator);
}

test "pipes and logical operators" {
    try expectTokens("echo hello | grep h && echo done", &[_]Token{ Token{ .word = "echo" }, Token{ .word = "hello" }, Token.pipe, Token{ .word = "grep" }, Token{ .word = "h" }, Token{ .word = "&&" }, Token{ .word = "echo" }, Token{ .word = "done" } }, testing.allocator);
}
