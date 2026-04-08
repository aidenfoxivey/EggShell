const std = @import("std");

const Token = union(enum) {
    word: []const u8,
    pipe, // |
    redirect_out, // >
    logical_and, // &&
    logical_or, // ||
};

fn tokenize(input: []const u8, allocator: Allocator) ![]Token {
    var tokens = ArrayList(Token).init(allocator);

    var i: usize = 0;
    while (i < input.len) {
        switch (input[i]) {
            ' ', '\t', '\n' => i += 1,

            '|' => {
                try tokens.append(.pipe);
                i += 1;
            },

            '>' => {
                if (i + 1 < input.len and input[i + 1] == '>') {
                    try tokens.append(.redirect_append);
                    i += 2;
                } else {
                    try tokens.append(.redirect_out);
                    i += 1;
                }
            },

            '"' => {
                const start = i + 1;
                i += 1;
                while (i < input.len and input[i] != '"') : (i += 1) {}
                const str = input[start..i];
                try tokens.append(.{ .word = str });
                i += 1; // skip closing quote
            },

            else => {
                const start = i;
                while (i < input.len and !isSpecial(input[i])) : (i += 1) {}
                try tokens.append(.{ .word = input[start..i] });
            },
        }
    }

    return tokens.toOwnedSlice();
}
