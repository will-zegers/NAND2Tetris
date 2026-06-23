const std = @import("std");
const Io = std.Io;
const fmt = std.fmt;
const mem = std.mem;
const Allocator = mem.Allocator;
const TokenIterator = mem.TokenIterator;
const testing = std.testing;

const CommandMap = @import("map/CommandMap.zig");
const CommandType = CommandMap.Type;

const OperationMap = @import("map/OperationMap.zig");
const Operation = OperationMap.Type;

const SegmentMap = @import("map/SegmentMap.zig");
const Segment = SegmentMap.Type;

const Self = @This();

const Arg1 = union {
    operation: Operation,
    segment: Segment,
    label: []const u8,
};

allocator: Allocator,
arg: [3]?[]const u8,
buffer: []u8,
commandMap: CommandMap,
operationMap: OperationMap,
segmentMap: SegmentMap,
commands: TokenIterator(u8, .scalar),

pub fn init(allocator: Allocator, io: Io, inputPath: []const u8) !Self {
    const buffer = try Io.Dir.cwd().readFileAlloc(io, inputPath, allocator, .unlimited);
    errdefer allocator.free(buffer);

    return .{
        .allocator = allocator,
        .arg = .{ null, null, null },
        .buffer = buffer,
        .commandMap = try .init(allocator),
        .operationMap = try .init(allocator),
        .segmentMap = try .init(allocator),
        .commands = mem.tokenizeScalar(u8, buffer, '\n'),
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.buffer);
    self.commandMap.deinit();
    self.operationMap.deinit();
    self.segmentMap.deinit();
}

pub fn advance(self: *Self) void {
    while (self.commands.next()) |next| {
        const command = trim(next);
        if (mem.startsWith(u8, command, "//")) {
            continue;
        }
        var currentCommand = mem.tokenizeScalar(u8, next, ' ');
        self.arg = [3]?[]const u8{
            currentCommand.next(),
            currentCommand.next(),
            currentCommand.next(),
        };
        return;
    }
    self.arg = [3]?[]const u8{ null, null, null };
}

pub fn hasMoreCommands(self: *Self) bool {
    while (self.commands.peek()) |next| {
        // Check if there's more instructions past comments and blank lines
        if (!mem.startsWith(u8, next, "//") and next.len != 0) {
            break;
        }
        _ = self.commands.next();
    }
    return self.commands.peek() != null;
}

pub fn commandType(self: Self) ?CommandType {
    const command = self.arg[0] orelse return null;

    return self.commandMap.get(command);
}

pub fn arg1(self: Self) ?Arg1 {
    switch (self.commandType().?) {
        .C_ARITHMETIC => {
            return Arg1{
                .operation = self.operationMap.get(self.arg[0].?),
            };
        },
        .C_CALL, .C_FUNCTION, .C_IF, .C_LABEL, .C_GOTO => {
            return Arg1{ .label = self.arg[1].? };
        },
        .C_PUSH, .C_POP => {
            return Arg1{
                .segment = self.segmentMap.get(self.arg[1].?),
            };
        },
        else => return null,
    }
}

pub fn arg2(self: Self) ?u16 {
    if (self.arg[2]) |arg| {
        return fmt.parseInt(u16, arg, 10) catch null;
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

test "smoke" {
    var parser = try init(testing.allocator, testing.io, "./test/BasicTest.vm");
    defer parser.deinit();
}

test "advance" {
    var parser = try init(testing.allocator, testing.io, "./test/BasicTest.vm");
    defer parser.deinit();
    try testing.expectEqual(parser.arg[0], null);
    parser.advance();
    try testing.expect(parser.arg[0] != null);
    for (0..24) |_| {
        parser.advance();
    }
    try testing.expect(parser.arg[0] != null);
    parser.advance();
    try testing.expectEqual(parser.arg[0], null);
}

test "hasMoreCommands" {
    var parser = try init(testing.allocator, testing.io, "./test/BasicTest.vm");
    defer parser.deinit();
    try testing.expect(parser.hasMoreCommands());
    parser.advance();
    try testing.expect(parser.hasMoreCommands());
    for (0..23) |_| {
        parser.advance();
    }
    try testing.expect(parser.hasMoreCommands());
    parser.advance();
    try testing.expect(!parser.hasMoreCommands());
}

test "commandType" {
    var parser = try init(testing.allocator, testing.io, "./test/BasicTest.vm");
    defer parser.deinit();
    parser.advance();
    try testing.expectEqual(parser.commandType(), .C_PUSH);
    parser.advance();
    try testing.expectEqual(parser.commandType(), .C_POP);
    for (0..15) |_| {
        parser.advance();
    }
    try testing.expectEqual(parser.commandType(), .C_ARITHMETIC);
    parser.advance();
    parser.advance();
    try testing.expectEqual(parser.commandType(), .C_ARITHMETIC);
}

test "arg1" {
    var parser = try init(testing.allocator, testing.io, "./test/BasicTest.vm");
    defer parser.deinit();
    parser.advance();
    try testing.expectEqual(parser.arg1().?.segment, .Constant);
    parser.advance();
    try testing.expectEqual(parser.arg1().?.segment, .Local);
    for (0..15) |_| {
        parser.advance();
    }
    try testing.expectEqual(parser.arg1().?.operation, .Add);
    parser.advance();
    parser.advance();
    try testing.expectEqual(parser.arg1().?.operation, .Sub);
}

test "arg2" {
    var parser = try init(testing.allocator, testing.io, "./test/BasicTest.vm");
    defer parser.deinit();
    parser.advance();
    try testing.expectEqual(parser.arg2().?, 10);
    parser.advance();
    try testing.expectEqual(parser.arg2().?, 0);
    parser.advance();
    parser.advance();
    parser.advance();
    try testing.expectEqual(parser.arg2().?, 2);
    parser.advance();
    parser.advance();
    parser.advance();
    try testing.expectEqual(parser.arg2().?, 6);
    parser.advance();
    parser.advance();
    parser.advance();
    try testing.expectEqual(parser.arg2().?, 5);
    for (0..6) |_| {
        parser.advance();
    }
    try testing.expect(parser.arg2() == null);
    parser.advance();
    parser.advance();
    try testing.expect(parser.arg2() == null);
}
