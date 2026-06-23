const std = @import("std");
const mem = std.mem;
const TokenIterator = mem.TokenIterator;
const Allocator = mem.Allocator;
const Io = std.Io;
const testing = std.testing;

const Self = @This();

const CommandType = enum {
    A_COMMAND,
    C_COMMAND,
    L_COMMAND,
};

allocator: Allocator,
buffer: []u8,
currentInstruction: ?[]const u8,
instructions: mem.TokenIterator(u8, .scalar),

pub fn init(inputFile: []const u8, io: Io, allocator: Allocator) !Self {
    const buffer = try Io.Dir.cwd().readFileAlloc(io, inputFile, allocator, .unlimited);
    errdefer allocator.free(buffer);

    return .{
        .allocator = allocator,
        .buffer = buffer,
        .currentInstruction = null,
        .instructions = mem.tokenizeScalar(u8, buffer, '\n'),
    };
}

pub fn deinit(self: Self) void {
    self.allocator.free(self.buffer);
}

pub fn reset(self: *Self) void {
    self.instructions.reset();
    self.currentInstruction = null;
}

pub fn hasMoreCommands(self: *Self) bool {
    while (self.instructions.peek()) |next| {
        // Check if there's more instructions past comments
        if (!mem.startsWith(u8, next, "//")) {
            break;
        }
        _ = self.instructions.next();
    }
    return self.instructions.peek() != null;
}

pub fn advance(self: *Self) void {
    while (self.instructions.next()) |next| {
        const instruction = trim(next);
        if (mem.startsWith(u8, instruction, "//")) {
            continue;
        }
        self.currentInstruction = instruction;
        return;
    }
    self.currentInstruction = null;
}

pub fn commandType(self: *Self) ?CommandType {
    if (self.currentInstruction) |instruction| {
        if (mem.startsWith(u8, instruction, "@")) {
            return .A_COMMAND;
        } else if (mem.startsWith(u8, instruction, "(") and mem.endsWith(u8, instruction, ")")) {
            return .L_COMMAND;
        } else if (mem.countScalar(u8, instruction, '=') > 0 or mem.countScalar(u8, instruction, ';') > 0) {
            return .C_COMMAND;
        }
    }

    return null;
}

pub fn symbol(self: *Self) ?[]const u8 {
    if (self.currentInstruction) |instr| {
        return switch (self.commandType().?) {
            .A_COMMAND => instr[1..], // remove '@'...
            .L_COMMAND => instr[1 .. instr.len - 1], // remove '(' ... ')'
            .C_COMMAND => null,
        };
    }

    return null;
}

pub fn dest(self: *Self) ?[]const u8 {
    if (mem.countScalar(u8, self.currentInstruction.?, '=') > 0) {
        var cInstruction = mem.tokenizeScalar(u8, self.currentInstruction.?, '=');
        return cInstruction.next();
    }
    return null;
}

pub fn comp(self: *Self) ?[]const u8 {
    var it: TokenIterator(u8, .scalar) = undefined;
    if (mem.countScalar(u8, self.currentInstruction.?, ';') > 0) {
        it = mem.tokenizeScalar(u8, self.currentInstruction.?, ';');
    } else {
        it = mem.tokenizeScalar(u8, self.currentInstruction.?, '=');
        _ = it.next();
    }

    return it.next();
}

pub fn jump(self: *Self) ?[]const u8 {
    if (mem.countScalar(u8, self.currentInstruction.?, ';') > 0) {
        var cInstruction = mem.splitScalar(u8, self.currentInstruction.?, ';');
        _ = cInstruction.next();
        return cInstruction.next();
    }
    return null;
}

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

const TEST_FILE: []const u8 = "./test/Rect.asm";

test "smoke" {
    const parser = try init(TEST_FILE, testing.io, testing.allocator);
    defer parser.deinit();
}

test "hasMoreCommands" {
    var parser = try init(TEST_FILE, testing.io, testing.allocator);
    defer parser.deinit();

    try testing.expect(parser.hasMoreCommands());
    parser.advance();
    try testing.expect(parser.hasMoreCommands());
    for (0..31) |_| {
        parser.advance();
    }
    try testing.expect(!parser.hasMoreCommands());
}

test "advance" {
    var parser = try init(TEST_FILE, testing.io, testing.allocator);
    defer parser.deinit();

    try testing.expect(parser.currentInstruction == null);
    for (0..27) |_| {
        parser.advance();
    }
    try testing.expect(parser.currentInstruction != null);
    parser.advance();
    try testing.expect(parser.currentInstruction == null);
}

test "commandType" {
    var parser = try init(TEST_FILE, testing.io, testing.allocator);
    defer parser.deinit();

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
    var parser = try init(TEST_FILE, testing.io, testing.allocator);
    defer parser.deinit();

    parser.advance();
    try testing.expectEqualStrings("R0", parser.symbol().?);
    for (0..6) |_| {
        parser.advance();
    }
    try testing.expectEqualStrings("SCREEN", parser.symbol().?);
    for (0..4) |_| {
        parser.advance();
    }
    try testing.expectEqualStrings("LOOP", parser.symbol().?);
}

test "dest" {
    var parser = try init(TEST_FILE, testing.io, testing.allocator);
    defer parser.deinit();

    parser.advance();
    parser.advance();
    try testing.expectEqualStrings("D", parser.dest().?);
    for (0..3) |_| {
        parser.advance();
    }
    try testing.expectEqual(parser.dest(), null);
    for (0..5) |_| {
        parser.advance();
    }
    try testing.expectEqualStrings("M", parser.dest().?);
}

test "comp" {
    var parser = try init(TEST_FILE, testing.io, testing.allocator);
    defer parser.deinit();

    parser.advance();
    try testing.expectEqual(parser.comp(), null);
    parser.advance();
    try testing.expectEqualStrings("M", parser.comp().?);
    for (0..12) |_| {
        parser.advance();
    }
    try testing.expectEqualStrings("-1", parser.comp().?);
    for (0..4) |_| {
        parser.advance();
    }
    try testing.expectEqualStrings("D+A", parser.comp().?);
}

test "jump" {
    var parser = try init(TEST_FILE, testing.io, testing.allocator);
    defer parser.deinit();

    for (0..3) |_| {
        parser.advance();
        try testing.expectEqual(parser.jump(), null);
    }
    parser.advance();
    try testing.expectEqualStrings("JLE", parser.jump().?);
    for (0..19) |_| {
        parser.advance();
        try testing.expectEqual(parser.jump(), null);
    }
    parser.advance();
    try testing.expectEqualStrings("JGT", parser.jump().?);
    for (0..2) |_| {
        parser.advance();
        try testing.expectEqual(parser.jump(), null);
    }
    parser.advance();
    try testing.expectEqualStrings("JMP", parser.jump().?);
}

test "reset" {
    var parser = try init(TEST_FILE, testing.io, testing.allocator);
    defer parser.deinit();

    parser.advance();
    const firstInstr = parser.currentInstruction;
    try testing.expect(null != firstInstr);
    parser.advance();
    const secondInstr = parser.currentInstruction;
    try testing.expect(null != secondInstr);
    parser.advance();
    const thirdInstr = parser.currentInstruction;
    try testing.expect(null != thirdInstr);
    for (1..10) |_| {
        parser.advance();
    }

    parser.reset();
    try testing.expectEqual(null, parser.symbol());
    parser.advance();
    try testing.expectEqual(firstInstr, parser.currentInstruction);
    parser.advance();
    try testing.expectEqual(secondInstr, parser.currentInstruction);
    parser.advance();
    try testing.expectEqual(thirdInstr, parser.currentInstruction);
}
