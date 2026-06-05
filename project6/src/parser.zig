const std = @import("std");
const testing = std.testing;

const util = @import("util.zig");

const BUFFER_SIZE = 1024 * 1024;

const CommandType = enum {
    A_COMMAND,
    C_COMMAND,
    L_COMMAND,
};

pub const Parser = struct {
    const Self = @This();

    pc_value: usize,
    bytes_out: usize,
    file_line_num: usize,
    current_instruction: ?[]const u8,
    instructions: std.mem.SplitIterator(u8, .scalar),

    pub fn init(input: []const u8) !Self {
        return Self{
            .pc_value = 0,
            .bytes_out = 0,
            .file_line_num = 0,
            .current_instruction = null,
            .instructions = std.mem.splitScalar(u8, input, '\n'),
        };
    }

    pub fn hasMoreCommands(self: *Self) bool {
        while (self.instructions.peek()) |next| {
            // Check if there's more instructions past comments and blank lines
            if (!std.mem.startsWith(u8, next, "//") and next.len != 0) {
                break;
            }
            _ = self.instructions.next();
        }
        return self.instructions.peek() != null;
    }

    pub fn advance(self: *Self) void {
        while (self.instructions.next()) |next| {
            const instruction = trim(next);
            if (std.mem.startsWith(u8, instruction, "//") or next.len == 0) {
                continue;
            }
            self.current_instruction = instruction;
            return;
        }
        self.current_instruction = null;
    }

    pub fn commandType(self: *Self) ?CommandType {
        if (self.current_instruction == null) {
            return null;
        } else if (std.mem.startsWith(u8, self.current_instruction.?, "@")) {
            return .A_COMMAND;
        } else if (std.mem.startsWith(u8, self.current_instruction.?, "(") and std.mem.endsWith(u8, self.current_instruction.?, ")")) {
            return .L_COMMAND;
        } else if (util.contains(self.current_instruction.?, '=') or util.contains(self.current_instruction.?, ';')) {
            return .C_COMMAND;
        }

        return null;
    }

    pub fn symbol(self: *Self) ?[]const u8 {
        const length = self.current_instruction.?.len;
        if (self.commandType() == .A_COMMAND) {
            return self.current_instruction.?[1..];
        } else if (self.commandType() == .L_COMMAND) {
            return self.current_instruction.?[1 .. length - 1];
        }
        return null;
    }

    pub fn dest(self: *Self) ?[]const u8 {
        if (!util.contains(self.current_instruction.?, '=')) {
            return null;
        }

        var c_instruction = std.mem.splitScalar(u8, self.current_instruction.?, '=');
        return c_instruction.first();
    }

    pub fn comp(self: *Self) ?[]const u8 {
        if (util.contains(self.current_instruction.?, ';')) {
            var c_instruction = std.mem.splitScalar(u8, self.current_instruction.?, ';');
            return c_instruction.first();
        }

        var c_instruction = std.mem.splitScalar(u8, self.current_instruction.?, '=');
        _ = c_instruction.next();
        return c_instruction.next();
    }

    pub fn jump(self: *Self) ?[]const u8 {
        if (!util.contains(self.current_instruction.?, ';')) {
            return null;
        }

        var c_instruction = std.mem.splitScalar(u8, self.current_instruction.?, ';');
        _ = c_instruction.next();
        return c_instruction.next();
    }
};

fn trim(string: []const u8) []const u8 {
    var start_index: usize = 0;
    for (string) |c| {
        if (!isWhiteSpace(c)) {
            break;
        }
        start_index += 1;
    }

    var end_index: usize = string.len;
    for (0..string.len) |i| {
        if (!isWhiteSpace(string[string.len - i - 1])) {
            break;
        }
        end_index -= 1;
    }

    return string[start_index..end_index];
}

fn isWhiteSpace(char: u8) bool {
    return (char == '\t' or char == ' ');
}

test "smoke" {
    var file_buffer: [BUFFER_SIZE]u8 = undefined;
    const length = try util.readASMFile("./test/Test.asm", &file_buffer, testing.io);

    const parser = try Parser.init(file_buffer[0..length]);
    try testing.expect(@TypeOf(parser) == Parser);
}

test "hasMoreCommands" {
    var file_buffer: [BUFFER_SIZE]u8 = undefined;
    const length = try util.readASMFile("./test/Test.asm", &file_buffer, testing.io);
    var parser = try Parser.init(file_buffer[0..length]);

    try testing.expect(parser.hasMoreCommands());
    parser.advance();
    try testing.expect(parser.hasMoreCommands());
    for (0..31) |_| {
        parser.advance();
    }
    try testing.expect(!parser.hasMoreCommands());
}

test "advance" {
    var file_buffer: [BUFFER_SIZE:0]u8 = undefined;
    const length = try util.readASMFile("./test/Test.asm", &file_buffer, testing.io);
    var parser = try Parser.init(file_buffer[0..length]);

    try testing.expect(parser.current_instruction == null);
    for (0..27) |_| {
        parser.advance();
    }
    try testing.expect(parser.current_instruction != null);
    parser.advance();
    try testing.expect(parser.current_instruction == null);
}

test "commandType" {
    var file_buffer: [BUFFER_SIZE]u8 = undefined;
    const length = try util.readASMFile("./test/Test.asm", &file_buffer, testing.io);
    var parser = try Parser.init(file_buffer[0..length]);

    parser.advance();
    try testing.expect(parser.commandType().? == .A_COMMAND);
    parser.advance();
    try testing.expect(parser.commandType().? == .C_COMMAND);
    for (0..9) |_| {
        parser.advance();
    }
    try testing.expect(parser.commandType().? == .L_COMMAND);
}

test "symbol" {
    var file_buffer: [BUFFER_SIZE]u8 = undefined;
    const length = try util.readASMFile("./test/Test.asm", &file_buffer, testing.io);
    var parser = try Parser.init(file_buffer[0..length]);

    parser.advance();
    try testing.expect(std.mem.eql(u8, parser.symbol().?, "R0"));
    for (0..6) |_| {
        parser.advance();
    }
    try testing.expect(std.mem.eql(u8, parser.symbol().?, "SCREEN"));
    for (0..4) |_| {
        parser.advance();
    }
    try testing.expect(std.mem.eql(u8, parser.symbol().?, "LOOP"));
}

test "dest" {
    var file_buffer: [BUFFER_SIZE]u8 = undefined;
    const length = try util.readASMFile("./test/Test.asm", &file_buffer, testing.io);
    var parser = try Parser.init(file_buffer[0..length]);

    parser.advance();
    parser.advance();
    try testing.expect(std.mem.eql(u8, parser.dest().?, "D"));
    for (0..3) |_| {
        parser.advance();
    }
    try testing.expect(parser.dest() == null);
    for (0..5) |_| {
        parser.advance();
    }
    try testing.expect(std.mem.eql(u8, parser.dest().?, "M"));
}

test "comp" {
    var file_buffer: [BUFFER_SIZE]u8 = undefined;
    const length = try util.readASMFile("./test/Test.asm", &file_buffer, testing.io);
    var parser = try Parser.init(file_buffer[0..length]);

    parser.advance();
    try testing.expect(parser.comp() == null);
    parser.advance();
    try testing.expect(std.mem.eql(u8, parser.comp().?, "M"));
    for (0..12) |_| {
        parser.advance();
    }
    try testing.expect(std.mem.eql(u8, parser.comp().?, "-1"));
    for (0..4) |_| {
        parser.advance();
    }
    try testing.expect(std.mem.eql(u8, parser.comp().?, "D+A"));
}

test "jump" {
    var file_buffer: [BUFFER_SIZE]u8 = undefined;
    const length = try util.readASMFile("./test/Test.asm", &file_buffer, testing.io);
    var parser = try Parser.init(file_buffer[0..length]);

    for (0..3) |_| {
        parser.advance();
        try testing.expect(parser.jump() == null);
    }
    parser.advance();
    try testing.expect(std.mem.eql(u8, parser.jump().?, "JLE"));
    for (0..19) |_| {
        parser.advance();
        try testing.expect(parser.jump() == null);
    }
    parser.advance();
    try testing.expect(std.mem.eql(u8, parser.jump().?, "JGT"));
    for (0..2) |_| {
        parser.advance();
        try testing.expect(parser.jump() == null);
    }
    parser.advance();
    try testing.expect(std.mem.eql(u8, parser.jump().?, "JMP"));
}
