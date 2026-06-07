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

    pcValue: usize,
    bytesOut: usize,
    fileLineNumber: usize,
    currentInstruction: ?[]const u8,
    instructions: std.mem.SplitIterator(u8, .scalar),

    pub fn init(input: []const u8) !Self {
        return Self{
            .pcValue = 0,
            .bytesOut = 0,
            .fileLineNumber = 0,
            .currentInstruction = null,
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
            self.currentInstruction = instruction;
            return;
        }
        self.currentInstruction = null;
    }

    pub fn commandType(self: *Self) ?CommandType {
        if (self.currentInstruction == null) {
            return null;
        } else if (std.mem.startsWith(u8, self.currentInstruction.?, "@")) {
            return .A_COMMAND;
        } else if (std.mem.startsWith(u8, self.currentInstruction.?, "(") and std.mem.endsWith(u8, self.currentInstruction.?, ")")) {
            return .L_COMMAND;
        } else if (util.contains(self.currentInstruction.?, '=') or util.contains(self.currentInstruction.?, ';')) {
            return .C_COMMAND;
        }

        return null;
    }

    pub fn symbol(self: *Self) ?[]const u8 {
        const length = self.currentInstruction.?.len;
        if (self.commandType() == .A_COMMAND) {
            return self.currentInstruction.?[1..];
        } else if (self.commandType() == .L_COMMAND) {
            return self.currentInstruction.?[1 .. length - 1];
        }
        return null;
    }

    pub fn dest(self: *Self) ?[]const u8 {
        if (!util.contains(self.currentInstruction.?, '=')) {
            return null;
        }

        var cInstruction = std.mem.splitScalar(u8, self.currentInstruction.?, '=');
        return cInstruction.first();
    }

    pub fn comp(self: *Self) ?[]const u8 {
        if (util.contains(self.currentInstruction.?, ';')) {
            var cInstruction = std.mem.splitScalar(u8, self.currentInstruction.?, ';');
            return cInstruction.first();
        }

        var cInstruction = std.mem.splitScalar(u8, self.currentInstruction.?, '=');
        _ = cInstruction.next();
        return cInstruction.next();
    }

    pub fn jump(self: *Self) ?[]const u8 {
        if (!util.contains(self.currentInstruction.?, ';')) {
            return null;
        }

        var cInstruction = std.mem.splitScalar(u8, self.currentInstruction.?, ';');
        _ = cInstruction.next();
        return cInstruction.next();
    }
};

fn trim(string: []const u8) []const u8 {
    var startIndex: usize = 0;
    for (string) |c| {
        if (!isWhiteSpace(c)) {
            break;
        }
        startIndex += 1;
    }

    var endIndex: usize = string.len;
    for (0..string.len) |i| {
        if (!isWhiteSpace(string[string.len - i - 1])) {
            break;
        }
        endIndex -= 1;
    }

    return string[startIndex..endIndex];
}

fn isWhiteSpace(char: u8) bool {
    return (char == '\t' or char == ' ');
}

test "smoke" {
    var fileBuffer: [BUFFER_SIZE]u8 = undefined;
    const length = try util.readASMFile("./test/Test.asm", &fileBuffer, testing.io);

    const parser = try Parser.init(fileBuffer[0..length]);
    try testing.expect(@TypeOf(parser) == Parser);
}

test "hasMoreCommands" {
    var fileBuffer: [BUFFER_SIZE]u8 = undefined;
    const length = try util.readASMFile("./test/Test.asm", &fileBuffer, testing.io);
    var parser = try Parser.init(fileBuffer[0..length]);

    try testing.expect(parser.hasMoreCommands());
    parser.advance();
    try testing.expect(parser.hasMoreCommands());
    for (0..31) |_| {
        parser.advance();
    }
    try testing.expect(!parser.hasMoreCommands());
}

test "advance" {
    var fileBuffer: [BUFFER_SIZE:0]u8 = undefined;
    const length = try util.readASMFile("./test/Test.asm", &fileBuffer, testing.io);
    var parser = try Parser.init(fileBuffer[0..length]);

    try testing.expect(parser.currentInstruction == null);
    for (0..27) |_| {
        parser.advance();
    }
    try testing.expect(parser.currentInstruction != null);
    parser.advance();
    try testing.expect(parser.currentInstruction == null);
}

test "commandType" {
    var fileBuffer: [BUFFER_SIZE]u8 = undefined;
    const length = try util.readASMFile("./test/Test.asm", &fileBuffer, testing.io);
    var parser = try Parser.init(fileBuffer[0..length]);

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
    var fileBuffer: [BUFFER_SIZE]u8 = undefined;
    const length = try util.readASMFile("./test/Test.asm", &fileBuffer, testing.io);
    var parser = try Parser.init(fileBuffer[0..length]);

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
    var fileBuffer: [BUFFER_SIZE]u8 = undefined;
    const length = try util.readASMFile("./test/Test.asm", &fileBuffer, testing.io);
    var parser = try Parser.init(fileBuffer[0..length]);

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
    var fileBuffer: [BUFFER_SIZE]u8 = undefined;
    const length = try util.readASMFile("./test/Test.asm", &fileBuffer, testing.io);
    var parser = try Parser.init(fileBuffer[0..length]);

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
    var fileBuffer: [BUFFER_SIZE]u8 = undefined;
    const length = try util.readASMFile("./test/Test.asm", &fileBuffer, testing.io);
    var parser = try Parser.init(fileBuffer[0..length]);

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
