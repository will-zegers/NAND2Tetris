const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const util = @import("util.zig");

const BUFFER_SIZE: usize = 1 * 1024 * 1024;

const CommandType = enum {
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

pub const Parser = struct {
    const Self = @This();

    allocator: mem.Allocator,
    buffer: []u8,
    currentCommand: ?[]const u8,
    commands: std.mem.SplitIterator(u8, .scalar),

    pub fn init(filepath: []const u8, io: std.Io, allocator: mem.Allocator) !Self {
        const buffer = try std.Io.Dir.cwd().readFileAlloc(io, filepath, allocator, .unlimited);

        // const buffer: []u8 = try allocator.alloc(u8, BUFFER_SIZE);
        // const bytes_in = try util.readFile(filepath, buffer, io);
        return Self{
            .allocator = allocator,
            .buffer = buffer,
            .currentCommand = null,
            .commands = std.mem.splitScalar(u8, buffer, '\n'),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buffer);
    }

    pub fn advance(self: *Self) void {
        while (self.commands.next()) |next| {
            const command = util.trim(next);
            if (std.mem.startsWith(u8, command, "//") or next.len == 0) {
                continue;
            }
            self.currentCommand = command;
            return;
        }
        self.currentCommand = null;
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
        const command = self.arg0();
        if (command == null) {
            return null;
        }

        if (mem.eql(u8, "add", command.?) or mem.eql(u8, "sub", command.?) or mem.eql(u8, "neg", command.?) or
            mem.eql(u8, "eq", command.?) or mem.eql(u8, "gt", command.?) or mem.eql(u8, "lt", command.?) or
            mem.eql(u8, "and", command.?) or mem.eql(u8, "or", command.?) or mem.eql(u8, "and", command.?))
        {
            return .C_ARITHMETIC;
        } else if (mem.eql(u8, "call", command.?)) {
            return .C_CALL;
        } else if (mem.eql(u8, "function", command.?)) {
            return .C_FUNCTION;
        } else if (mem.eql(u8, "goto", command.?)) {
            return .C_GOTO;
        } else if (mem.eql(u8, "if", command.?)) {
            return .C_IF;
        } else if (mem.eql(u8, "label", command.?)) {
            return .C_LABEL;
        } else if (mem.eql(u8, "pop", command.?)) {
            return .C_POP;
        } else if (mem.eql(u8, "push", command.?)) {
            return .C_PUSH;
        } else if (mem.eql(u8, "return", command.?)) {
            return .C_RETURN;
        } else {
            return null;
        }
    }

    pub fn arg0(self: Self) ?[]const u8 {
        if (self.currentCommand == null) {
            return null;
        }

        var command = mem.splitScalar(u8, self.currentCommand.?, ' ');
        return command.first();
    }

    pub fn arg1(self: Self) ?[]const u8 {
        if (self.currentCommand == null) {
            return null;
        }

        var command = mem.splitScalar(u8, self.currentCommand.?, ' ');
        if (self.commandType() == .C_ARITHMETIC) {
            return command.first();
        } else {
            _ = command.next();
            return command.next();
        }
    }

    pub fn arg2(self: Self) ?[]const u8 {
        if (self.currentCommand == null) {
            return null;
        }

        switch (self.commandType().?) {
            .C_CALL, .C_FUNCTION, .C_POP, .C_PUSH => {
                var command = mem.splitScalar(u8, self.currentCommand.?, ' ');
                _ = command.next();
                _ = command.next();
                return command.next();
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
    try testing.expect(parser.currentCommand == null);
    parser.advance();
    try testing.expect(parser.currentCommand != null);
    for (0..24) |_| {
        parser.advance();
    }
    try testing.expect(parser.currentCommand != null);
    parser.advance();
    try testing.expect(parser.currentCommand == null);
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
    try testing.expect(parser.commandType() == .C_PUSH);
    parser.advance();
    try testing.expect(parser.commandType() == .C_POP);
    for (0..15) |_| {
        parser.advance();
    }
    try testing.expect(parser.commandType() == .C_ARITHMETIC);
    parser.advance();
    parser.advance();
    try testing.expect(parser.commandType() == .C_ARITHMETIC);
}

test "arg1" {
    var parser = try Parser.init("./test/BasicTest.vm", testing.io, testing.allocator);
    defer parser.deinit();
    parser.advance();
    try testing.expect(mem.eql(u8, parser.arg1().?, "constant"));
    parser.advance();
    try testing.expect(mem.eql(u8, parser.arg1().?, "local"));
    for (0..15) |_| {
        parser.advance();
    }
    try testing.expect(mem.eql(u8, parser.arg1().?, "add"));
    parser.advance();
    parser.advance();
    try testing.expect(mem.eql(u8, parser.arg1().?, "sub"));
}

test "arg2" {
    var parser = try Parser.init("./test/BasicTest.vm", testing.io, testing.allocator);
    defer parser.deinit();
    parser.advance();
    try testing.expect(mem.eql(u8, parser.arg2().?, "10"));
    parser.advance();
    try testing.expect(mem.eql(u8, parser.arg2().?, "0"));
    parser.advance();
    parser.advance();
    parser.advance();
    try testing.expect(mem.eql(u8, parser.arg2().?, "2"));
    parser.advance();
    parser.advance();
    parser.advance();
    try testing.expect(mem.eql(u8, parser.arg2().?, "6"));
    parser.advance();
    parser.advance();
    parser.advance();
    try testing.expect(mem.eql(u8, parser.arg2().?, "5"));
    for (0..6) |_| {
        parser.advance();
    }
    try testing.expect(parser.arg2() == null);
    parser.advance();
    parser.advance();
    try testing.expect(parser.arg2() == null);
}
