const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const StringHashMap = std.StringHashMap;

const util = @import("util.zig");

const mCommand = @import("map/command.zig");
const CommandType = mCommand.CommandType;
const CommandTypeMap = mCommand.CommandTypeMap;

const mOperation = @import("map/operation.zig");
const Operation = mOperation.OperationType;
const OperationTypeMap = mOperation.OperationTypeMap;

const mSegment = @import("map/segment.zig");
const SegmentType = mSegment.SegmentType;
const SegmentTypeMap = mSegment.SegmentTypeMap;

pub const Arg1 = union {
    operation: Operation,
    segment: SegmentType,
    label: []const u8,
};

pub const Parser = struct {
    const Self = @This();

    allocator: mem.Allocator,
    arg: [3]?[]const u8,
    buffer: []u8,
    commandMap: CommandTypeMap,
    operationMap: OperationTypeMap,
    segmentMap: SegmentTypeMap,
    commands: mem.TokenIterator(u8, .scalar),

    pub fn init(filepath: []const u8, io: std.Io, allocator: mem.Allocator) !Self {
        const buffer = try std.Io.Dir.cwd().readFileAlloc(io, filepath, allocator, .unlimited);
        errdefer allocator.free(buffer);

        var commandMap = try CommandTypeMap.init(allocator);
        errdefer commandMap.deinit();

        var operationMap = try OperationTypeMap.init(allocator);
        errdefer operationMap.deinit();

        var segmentMap = try SegmentTypeMap.init(allocator);
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
        switch (self.commandType().?) {
            .C_ARITHMETIC => {
                return Arg1{
                    .operation = self.operationMap.get(self.arg[0].?).?,
                };
            },
            .C_IF, .C_LABEL, .C_GOTO => {
                return Arg1{ .label = self.arg[1].? };
            },
            .C_PUSH, .C_POP => {
                return Arg1{
                    .segment = self.segmentMap.get(self.arg[1].?).?,
                };
            },
            else => return null,
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
