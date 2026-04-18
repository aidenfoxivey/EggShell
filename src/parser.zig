const std = @import("std");
const testing = std.testing;

const Token = union(enum) {
    word: []const u8,
    pipe, // |
    logical_or, // ||
    background, // &
    logical_and, // &&
};

pub const Command = []const []const u8;
pub const Commands = []const Command;

const Node = union(enum) {
    // pipe(Node, Node),
    logical_or: struct { u32, u32 },
    logical_and: struct { u32, u32 },
    // background(Node),
    command: Command,
};

fn isSpecialCharacter(c: u8) bool {
    return switch (c) {
        ' ', '\n', '"', '|' => true,
        else => false,
    };
}

fn lex(input: []const u8, allocator: std.mem.Allocator) ![]Token {
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
                    try tokens.append(allocator, Token.logical_and);
                    i += 2;
                } else {
                    try tokens.append(allocator, Token.background);
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

const Parser = struct {
    gpa: std.mem.Allocator,
    tok_i: u64,
    tokens: []Token,
    nodes: std.ArrayList(Node) = .empty,

    fn peek(self: *Parser) Token {
        return self.tokens[self.tok_i];
    }

    fn consume(self: *Parser) Token {
        const token = self.peek();
        self.tok_i += 1;
        return token;
    }

    fn addNode(self: *Parser, node: Node) !u32 {
        const idx: u32 = @intCast(self.nodes.items.len);
        try self.nodes.append(self.gpa, node);
        return idx;
    }

    // foo || bar -> LogicalOr{ Command{ .{ "foo" } }, Command{ .{ "bar" } } }
    fn parseOr(self: *Parser) !u32 {
        var left: u32 = try self.parseAnd();

        while (self.tok_i < self.tokens.len and self.peek() == .logical_or) {
            _ = self.consume();
            const right = try self.parseAnd();
            left = try self.addNode(Node{ .logical_or = .{ left, right } });
        }

        return left;
    }

    // foo && bar -> LogicalAnd{ Command{ .{ "foo" } }, Command{ .{ "bar" } } }
    fn parseAnd(self: *Parser) !u32 {
        var left: u32 = try self.parseCommand();

        while (self.tok_i < self.tokens.len and self.peek() == .logical_and) {
            _ = self.consume();
            const right = try self.parseCommand();
            left = try self.addNode(Node{ .logical_and = .{ left, right } });
        }

        return left;
    }

    // echo --foo --bar "baz" -> Command{ .{ "echo", "--foo", "--bar", "baz" } }
    fn parseCommand(self: *Parser) !u32 {
        var argv: std.ArrayList([]const u8) = .empty;

        while (self.tok_i < self.tokens.len and self.peek() == .word) {
            const token = self.consume();
            try argv.append(self.gpa, token.word);
        }

        const n = Node{ .command = try argv.toOwnedSlice(self.gpa) };
        return self.addNode(n);
    }

    // For debugging and snap tests.
    fn printNode(self: *const Parser, writer: anytype, idx: u32) !void {
        const node = self.nodes.items[idx];
        switch (node) {
            .command => |argv| {
                try writer.writeAll("[");
                for (argv, 0..) |arg, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.writeAll(arg);
                }
                try writer.writeAll("]");
            },
            .logical_and => |pair| {
                try writer.writeAll("(and ");
                try self.printNode(writer, pair[0]);
                try writer.writeAll(" ");
                try self.printNode(writer, pair[1]);
                try writer.writeAll(")");
            },
            .logical_or => |pair| {
                try writer.writeAll("(or ");
                try self.printNode(writer, pair[0]);
                try writer.writeAll(" ");
                try self.printNode(writer, pair[1]);
                try writer.writeAll(")");
            },
        }
    }
};

pub fn parseCommands(input: []const u8, allocator: std.mem.Allocator) !struct { u32, []Node } {
    const tokens = try lex(input, allocator);
    var parser = Parser{
        .gpa = allocator,
        .tok_i = 0,
        .tokens = tokens,
    };
    const root = try parser.parserOr();
    return .{ root, try parser.nodes.toOwnedSlice(allocator) };
}

// Testing helper function.
fn expectTokens(input: []const u8, expected: []const Token) !void {
    const tokens = try lex(input, testing.allocator);
    defer testing.allocator.free(tokens);
    try testing.expectEqualDeep(expected, tokens);
}

// Must free individual command slices and the whole nodes array.
fn freeNodes(allocator: std.mem.Allocator, nodes: []Node) void {
    for (nodes) |node| {
        switch (node) {
            .command => |cmd| allocator.free(cmd),
            .logical_and, .logical_or => {},
        }
    }
    allocator.free(nodes);
}

fn expectCommands(input: []const u8, expected: []const Node) !void {
    _, const nodes = try parseCommands(input, testing.allocator);
    defer freeNodes(testing.allocator, nodes);
    try testing.expectEqualDeep(expected, nodes);
}

test "canonical example" {
    try expectTokens("echo hello world", &.{
        .{ .word = "echo" },
        .{ .word = "hello" },
        .{ .word = "world" },
    });
}

test "quotes" {
    try expectTokens("echo \"hello world\"", &.{
        .{ .word = "echo" },
        .{ .word = "hello world" },
    });
}

test "flags" {
    try expectTokens("compile --drafts main.mk", &.{
        .{ .word = "compile" },
        .{ .word = "--drafts" },
        .{ .word = "main.mk" },
    });
}

test "dot slash" {
    try expectTokens("./a.out", &.{
        .{ .word = "./a.out" },
    });
}

// TODO: Decide if an unmatched quote should be an error or if it should just assume until \n is the quote.
test "unmatched quote" {
    try expectTokens("echo \"hello world", &.{
        .{ .word = "echo" },
        .{ .word = "hello world" },
    });
}

test "leading and trailing spaces" {
    try expectTokens("   echo hello world   ", &.{ .{ .word = "echo" }, .{ .word = "hello" }, .{
        .word = "world",
    } });
}

test "pipes and logical operators" {
    try expectTokens(
        "echo hello | grep h && echo done &",
        &.{
            .{ .word = "echo" },
            .{ .word = "hello" },
            .pipe,
            .{ .word = "grep" },
            .{ .word = "h" },
            .logical_and,
            .{ .word = "echo" },
            .{ .word = "done" },
            .background,
        },
    );
}

const Snap = @import("snaptest.zig").Snap;
const snap = Snap.snap;

fn checkTree(input: []const u8, want: Snap) !void {
    const allocator = testing.allocator;
    const tokens = try lex(input, allocator);
    defer allocator.free(tokens);
    var parser = Parser{
        .gpa = allocator,
        .tok_i = 0,
        .tokens = tokens,
    };
    const root = try parser.parserOr();
    const nodes = try parser.nodes.toOwnedSlice(allocator);
    defer freeNodes(allocator, nodes);
    parser.nodes = .{ .items = nodes, .capacity = nodes.len };
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    try parser.printNode(buf.writer(allocator), root);
    try want.diff(buf.items);
}

test "snap: simple command" {
    try checkTree("echo hello world", snap(@src(),
        \\[echo, hello, world]
    ));
}

test "snap: logical and" {
    try checkTree("echo hello && echo bye", snap(@src(),
        \\(and [echo, hello] [echo, bye])
    ));
}

test "snap: operator precedence" {
    try checkTree("echo meep || echo hello && echo bye", snap(@src(),
        \\(or [echo, meep] (and [echo, hello] [echo, bye]))
    ));
}

test "snap: ambiguous symbols" {
    try checkTree("echo meep || \"||\"", snap(@src(),
        \\(or [echo, meep] [||])
    ));
}
