const std = @import("std");
const mem = std.mem;
const testing = std.testing;

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

pub const Parser = struct {
    const Self = @This();

    allocator: mem.Allocator,
    args: [3]?[]const u8,
    buffer: []u8,
    commandMap: CommandMap,
    commands: mem.TokenIterator(u8, .scalar),

    pub fn init(filepath: []const u8, io: std.Io, allocator: mem.Allocator) !Self {
        const buffer = try std.Io.Dir.cwd().readFileAlloc(io, filepath, allocator, .unlimited);
        errdefer allocator.free(buffer);

        const commandMap = try CommandMap.init(allocator);
        errdefer commandMap.deinit();

        return Self{
            .allocator = allocator,
            .args = [3]?[]const u8{ null, null, null },
            .buffer = buffer,
            .commandMap = commandMap,
            .commands = std.mem.tokenizeScalar(u8, buffer, '\n'),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buffer);
        self.commandMap.deinit();
    }

    pub fn advance(self: *Self) void {
        while (self.commands.next()) |next| {
            const command = util.trim(next);
            if (std.mem.startsWith(u8, command, "//")) {
                continue;
            }
            var currentCommand = mem.tokenizeScalar(u8, next, ' ');
            self.args = [3]?[]const u8{
                currentCommand.next(),
                currentCommand.next(),
                currentCommand.next(),
            };
            return;
        }
        self.args = [3]?[]const u8{ null, null, null };
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
        const command = self.args[0] orelse return null;

        return self.commandMap.get(command);
    }

    pub fn arg1(self: Self) ?[]const u8 {
        if (self.commandType() == .C_ARITHMETIC) {
            return self.args[0];
        } else {
            return self.args[1];
        }
    }

    pub fn arg2(self: Self) ?[]const u8 {
        switch (self.commandType().?) {
            .C_CALL, .C_FUNCTION, .C_POP, .C_PUSH => {
                return self.args[2];
            },
            else => return null,
        }
    }
};

test "smoke" {
    var parser = try Parser.init("./test/BasicTest.vm", testing.io, testing.allocator);
    defer parser.deinit();
}

test "advance" {
    var parser = try Parser.init("./test/BasicTest.vm", testing.io, testing.allocator);
    defer parser.deinit();
    try testing.expectEqual(parser.args[0], null);
    parser.advance();
    try testing.expect(parser.args[0] != null);
    for (0..24) |_| {
        parser.advance();
    }
    try testing.expect(parser.args[0] != null);
    parser.advance();
    try testing.expectEqual(parser.args[0], null);
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
    try testing.expectEqualStrings(parser.arg1().?, "constant");
    parser.advance();
    try testing.expectEqualStrings(parser.arg1().?, "local");
    for (0..15) |_| {
        parser.advance();
    }
    try testing.expectEqualStrings(parser.arg1().?, "add");
    parser.advance();
    parser.advance();
    try testing.expectEqualStrings(parser.arg1().?, "sub");
}

test "arg2" {
    var parser = try Parser.init("./test/BasicTest.vm", testing.io, testing.allocator);
    defer parser.deinit();
    parser.advance();
    try testing.expectEqualStrings(parser.arg2().?, "10");
    parser.advance();
    try testing.expectEqualStrings(parser.arg2().?, "0");
    parser.advance();
    parser.advance();
    parser.advance();
    try testing.expectEqualStrings(parser.arg2().?, "2");
    parser.advance();
    parser.advance();
    parser.advance();
    try testing.expectEqualStrings(parser.arg2().?, "6");
    parser.advance();
    parser.advance();
    parser.advance();
    try testing.expectEqualStrings(parser.arg2().?, "5");
    for (0..6) |_| {
        parser.advance();
    }
    try testing.expect(parser.arg2() == null);
    parser.advance();
    parser.advance();
    try testing.expect(parser.arg2() == null);
}
