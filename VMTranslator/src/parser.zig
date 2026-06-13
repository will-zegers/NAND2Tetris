const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const StringHashMap = std.StringHashMap;

const util = @import("util.zig");

const BUFFER_SIZE: usize = 1 * 1024 * 1024;

pub const CommandType = enum {
    C_ARITHMETIC,
    C_CALL,
    C_FUNCTION,
    C_GOTO,
    C_IF,
    C_LABEL,
    C_POP,
    C_PUSH,
    C_RETURN,
};

const CommandMap = struct {
    const Self = @This();

    allocator: mem.Allocator,
    map: std.StringHashMap(CommandType),

    pub fn init(allocator: mem.Allocator) !Self {
        var map = std.StringHashMap(CommandType).init(allocator);
        errdefer map.deinit();

        try map.put("add", .C_ARITHMETIC);
        try map.put("sub", .C_ARITHMETIC);
        try map.put("neg", .C_ARITHMETIC);
        try map.put("eq", .C_ARITHMETIC);
        try map.put("gt", .C_ARITHMETIC);
        try map.put("lt", .C_ARITHMETIC);
        try map.put("and", .C_ARITHMETIC);
        try map.put("or", .C_ARITHMETIC);
        try map.put("not", .C_ARITHMETIC);
        try map.put("call", .C_CALL);
        try map.put("function", .C_FUNCTION);
        try map.put("goto", .C_GOTO);
        try map.put("if", .C_IF);
        try map.put("label", .C_LABEL);
        try map.put("pop", .C_POP);
        try map.put("push", .C_PUSH);
        try map.put("return", .C_RETURN);

        return Self{ .allocator = allocator, .map = map };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
    }

    pub fn get(self: Self, key: []const u8) ?CommandType {
        return self.map.get(key);
    }
};

pub const ArithmeticOperation = enum {
    Add,
    Sub,
    And,
    Or,
    Neg,
    Not,
    Eq,
    Lt,
    Gt,
};

const OperationMap = struct {
    const Self = @This();

    map: StringHashMap(ArithmeticOperation),

    pub fn init(allocator: mem.Allocator) !Self {
        var map = StringHashMap(ArithmeticOperation).init(allocator);
        errdefer map.deinit();

        try map.put("add", .Add);
        try map.put("sub", .Sub);
        try map.put("and", .And);
        try map.put("or", .Or);
        try map.put("neg", .Neg);
        try map.put("not", .Not);
        try map.put("eq", .Eq);
        try map.put("lt", .Lt);
        try map.put("gt", .Gt);

        return Self{ .map = map };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
    }

    pub fn get(self: Self, key: []const u8) ?ArithmeticOperation {
        return self.map.get(key);
    }
};

pub const Segment = enum {
    LCL,
    ARG,
    Pointer,
    This,
    That,
    Temp,
    Static,
    Constant,
};

const SegmentMap = struct {
    const Self = @This();

    map: StringHashMap(Segment),

    pub fn init(allocator: mem.Allocator) !Self {
        var map = StringHashMap(Segment).init(allocator);
        errdefer map.deinit();

        try map.put("local", .LCL);
        try map.put("argument", .ARG);
        try map.put("pointer", .Pointer);
        try map.put("this", .This);
        try map.put("that", .That);
        try map.put("temp", .Temp);
        try map.put("static", .Static);
        try map.put("constant", .Constant);

        return Self{ .map = map };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
    }

    pub fn get(self: Self, key: []const u8) ?Segment {
        return self.map.get(key);
    }
};

pub const Arg1 = union {
    operation: ArithmeticOperation,
    segment: Segment,
};

pub const Parser = struct {
    const Self = @This();

    allocator: mem.Allocator,
    arg: [3]?[]const u8,
    buffer: []u8,
    commandMap: CommandMap,
    operationMap: OperationMap,
    segmentMap: SegmentMap,
    commands: mem.TokenIterator(u8, .scalar),

    pub fn init(filepath: []const u8, io: std.Io, allocator: mem.Allocator) !Self {
        const buffer = try std.Io.Dir.cwd().readFileAlloc(io, filepath, allocator, .unlimited);
        errdefer allocator.free(buffer);

        var commandMap = try CommandMap.init(allocator);
        errdefer commandMap.deinit();

        var operationMap = try OperationMap.init(allocator);
        errdefer operationMap.deinit();

        var segmentMap = try SegmentMap.init(allocator);
        errdefer segmentMap.deinit();

        return Self{
            .allocator = allocator,
            .arg = [3]?[]const u8{ null, null, null },
            .buffer = buffer,
            .commandMap = commandMap,
            .operationMap = operationMap,
            .segmentMap = segmentMap,
            .commands = std.mem.tokenizeScalar(u8, buffer, '\n'),
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
            const command = util.trim(next);
            if (std.mem.startsWith(u8, command, "//")) {
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
            if (!std.mem.startsWith(u8, next, "//") and next.len != 0) {
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
        if (self.commandType() == .C_ARITHMETIC) {
            return Arg1{
                .operation = self.operationMap.get(self.arg[0].?).?,
            };
        } else {
            return Arg1{
                .segment = self.segmentMap.get(self.arg[1].?).?,
            };
        }
    }

    pub fn arg2(self: Self) ?u16 {
        if (self.arg[2]) |arg| {
            return std.fmt.parseInt(u16, arg, 10) catch null;
        }
        return null;
    }
};

test "smoke" {
    var parser = try Parser.init("./test/BasicTest.vm", testing.io, testing.allocator);
    defer parser.deinit();
}

test "advance" {
    var parser = try Parser.init("./test/BasicTest.vm", testing.io, testing.allocator);
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
    var parser = try Parser.init("./test/BasicTest.vm", testing.io, testing.allocator);
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
    var parser = try Parser.init("./test/BasicTest.vm", testing.io, testing.allocator);
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
    var parser = try Parser.init("./test/BasicTest.vm", testing.io, testing.allocator);
    defer parser.deinit();
    parser.advance();
    try testing.expectEqual(parser.arg1().?.segment, .Constant);
    parser.advance();
    try testing.expectEqual(parser.arg1().?.segment, .LCL);
    for (0..15) |_| {
        parser.advance();
    }
    try testing.expectEqual(parser.arg1().?.operation, .Add);
    parser.advance();
    parser.advance();
    try testing.expectEqual(parser.arg1().?.operation, .Sub);
}

test "arg2" {
    var parser = try Parser.init("./test/BasicTest.vm", testing.io, testing.allocator);
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
