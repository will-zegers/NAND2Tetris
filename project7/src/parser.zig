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

    currentCommand: ?[]const u8,
    commands: std.mem.SplitIterator(u8, .scalar),

    pub fn init(input: []const u8) Self {
        return Self{
            .currentCommand = null,
            .commands = std.mem.splitScalar(u8, input, '\n'),
        };
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
        const command = self.arg1();
        if (command == null) {
            return null;
        }

        if (mem.eql(u8, "add", command.?) or mem.eql(u8, "sub", command.?)) {
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

    pub fn arg1(self: Self) ?[]const u8 {
        if (self.currentCommand == null) {
            return null;
        }

        var command = mem.splitScalar(u8, self.currentCommand.?, ' ');
        return command.first();
    }

    pub fn arg2(self: Self) ?[]const u8 {
        if (self.currentCommand == null) {
            return null;
        }

        switch (self.commandType().?) {
            .C_CALL, .C_FUNCTION, .C_POP, .C_PUSH => {
                var command = mem.splitScalar(u8, self.currentCommand.?, ' ');
                _ = command.next();
                return command.next();
            },
            else => return null,
        }
    }
};

test "smoke" {
    const parser = Parser.init("./test/Test.vm");
    _ = parser;
}

test "advance" {
    var fileBuffer: [BUFFER_SIZE]u8 = undefined;
    const length = try util.readFile("./test/Test.vm", &fileBuffer, testing.io);
    var parser = Parser.init(fileBuffer[0..length]);
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
    var fileBuffer: [BUFFER_SIZE]u8 = undefined;
    const length = try util.readFile("./test/Test.vm", &fileBuffer, testing.io);
    var parser = Parser.init(fileBuffer[0..length]);
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
    var fileBuffer: [BUFFER_SIZE]u8 = undefined;
    const length = try util.readFile("./test/Test.vm", &fileBuffer, testing.io);
    var parser = Parser.init(fileBuffer[0..length]);
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
    var fileBuffer: [BUFFER_SIZE]u8 = undefined;
    const length = try util.readFile("./test/Test.vm", &fileBuffer, testing.io);
    var parser = Parser.init(fileBuffer[0..length]);
    parser.advance();
    try testing.expect(mem.eql(u8, parser.arg1().?, "push"));
    parser.advance();
    try testing.expect(mem.eql(u8, parser.arg1().?, "pop"));
    for (0..15) |_| {
        parser.advance();
    }
    try testing.expect(mem.eql(u8, parser.arg1().?, "add"));
    parser.advance();
    parser.advance();
    try testing.expect(mem.eql(u8, parser.arg1().?, "sub"));
}

test "arg2" {
    var fileBuffer: [BUFFER_SIZE]u8 = undefined;
    const length = try util.readFile("./test/Test.vm", &fileBuffer, testing.io);
    var parser = Parser.init(fileBuffer[0..length]);
    parser.advance();
    try testing.expect(mem.eql(u8, parser.arg2().?, "constant"));
    parser.advance();
    try testing.expect(mem.eql(u8, parser.arg2().?, "local"));
    parser.advance();
    parser.advance();
    parser.advance();
    try testing.expect(mem.eql(u8, parser.arg2().?, "argument"));
    parser.advance();
    parser.advance();
    parser.advance();
    try testing.expect(mem.eql(u8, parser.arg2().?, "this"));
    parser.advance();
    parser.advance();
    parser.advance();
    try testing.expect(mem.eql(u8, parser.arg2().?, "that"));
    for (0..6) |_| {
        parser.advance();
    }
    try testing.expect(parser.arg2() == null);
    parser.advance();
    parser.advance();
    try testing.expect(parser.arg2() == null);
}
