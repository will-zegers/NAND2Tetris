const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const testing = std.testing;
const AutoHashMap = std.AutoHashMap;
const Random = std.Random;

const util = @import("util.zig");

const arithmetic = @import("arithmetic.zig");
const UnaryTemplate = arithmetic.UnaryTemplate;
const BinaryTemplate = arithmetic.BinaryTemplate;
const CompareTemplate = arithmetic.CompareTemplate;

const mAddress = @import("map/address.zig");
const BaseAddressMap = mAddress.BaseAddressMap;

const mCommand = @import("map/command.zig");
const CommandType = mCommand.CommandType;

const mOperation = @import("map/operation.zig");
const OperationType = mOperation.OperationType;

const mSegment = @import("map/segment.zig");
const SegmentType = mSegment.SegmentType;

const LABEL_SIZE: usize = 5;

pub const CodeWriter = struct {
    const Self = @This();

    allocator: mem.Allocator,
    instructions: std.ArrayList([]const u8),
    baseAddrTable: BaseAddressMap,
    outputPath: []const u8,
    rng: Random.IoSource,

    pub fn init(io: std.Io, allocator: mem.Allocator) !Self {
        var baseAddrTable = try BaseAddressMap.init(allocator);
        errdefer baseAddrTable.deinit();

        return Self{
            .allocator = allocator,
            .instructions = try .initCapacity(allocator, 512),
            .baseAddrTable = baseAddrTable,
            .outputPath = undefined,
            .rng = .{ .io = io },
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.instructions.items) |item| {
            self.allocator.free(item);
        }
        defer self.instructions.deinit(self.allocator);
        defer self.baseAddrTable.deinit();
    }

    pub fn setFileName(self: *Self, outputPath: []const u8) void {
        self.outputPath = outputPath;
    }

    pub fn writeInit(self: *Self) !void {
        const bootstrap =
            \\@256
            \\D=A
            \\@0
            \\M=D
            \\@300
            \\D=A
            \\@1
            \\M=D
            \\@400
            \\D=A
            \\@2
            \\M=D
            \\@3000
            \\D=A
            \\@3
            \\M=D
            \\@3010
            \\D=A
            \\@4
            \\M=D
            // TODO: Call Sys.init
        ;
        try self.instructions.append(self.allocator, try self.allocator.dupe(u8, bootstrap));
    }

    pub fn writeArithmetic(self: *Self, operation: OperationType) !void {
        const buf: []const u8 = switch (operation) {
            .Add => try fmt.allocPrint(self.allocator, BinaryTemplate, .{"M=D+M"}),
            .Sub => try fmt.allocPrint(self.allocator, BinaryTemplate, .{"M=M-D"}),
            .And => try fmt.allocPrint(self.allocator, BinaryTemplate, .{"M=D&M"}),
            .Or => try fmt.allocPrint(self.allocator, BinaryTemplate, .{"M=D|M"}),
            .Neg => try fmt.allocPrint(self.allocator, UnaryTemplate, .{"M=-M"}),
            .Not => try fmt.allocPrint(self.allocator, UnaryTemplate, .{"M=!M"}),
            .Eq, .Lt, .Gt => |compare| blk: {
                const label = self.generateLabel();
                const jumpType = switch (compare) {
                    .Eq => "JEQ",
                    .Lt => "JLT",
                    .Gt => "JGT",
                    else => unreachable,
                };
                break :blk try std.fmt.allocPrint(self.allocator, CompareTemplate, .{ label, jumpType });
            },
        };

        try self.instructions.append(self.allocator, buf);
    }

    /// Generate a random label to be embbed in the output code
    fn generateLabel(self: Self) [LABEL_SIZE]u8 {
        const iRng = self.rng.interface();

        var label = [LABEL_SIZE]u8{ 0, 0, 0, 0, 0 };
        for (0..LABEL_SIZE) |i| {
            label[i] = iRng.intRangeAtMost(u8, 'a', 'z');
        }
        return label;
    }

    pub fn writePushPop(self: *Self, commandType: CommandType, segment: SegmentType, index: u16) !void {
        var buf: []u8 = undefined;
        switch (commandType) {
            .C_PUSH => {
                switch (segment) {
                    .LCL, .ARG, .This, .That, .Pointer => {
                        const template =
                            \\@{d}
                            \\D=A
                            \\@{c}
                            \\D=D+M
                            \\A=D
                            \\D=M
                            \\@SP
                            \\A=M
                            \\M=D
                            \\@SP
                            \\M=M+1
                        ;
                        const pAddr: u8 = switch (segment) {
                            .LCL => '1',
                            .ARG => '2',
                            .This, .Pointer => '3',
                            .That => '4',
                            else => unreachable,
                        };
                        buf = try std.fmt.allocPrint(self.allocator, template, .{ index, pAddr });
                    },
                    else => {
                        const baseAddr = self.baseAddrTable.get(segment).?;
                        const addrOffset = baseAddr + index;

                        const template =
                            \\@{d}
                            \\D={c}
                            \\@SP
                            \\A=M
                            \\M=D
                            \\@SP
                            \\M=M+1
                        ;
                        const source: u8 = if (segment == .Constant) 'A' else 'M';
                        buf = try std.fmt.allocPrint(self.allocator, template, .{ addrOffset, source });
                    },
                }
            },
            .C_POP => {
                switch (segment) {
                    .LCL, .ARG, .This, .That, .Pointer => {
                        const template =
                            \\@{d}
                            \\D=A
                            \\@{c}
                            \\D=D+M
                            \\@SP
                            \\AM=M-1
                            \\D=D+M
                            \\A=D-M
                            \\D=D-A
                            \\M=D
                        ;
                        const pAddr: u8 = switch (segment) {
                            .LCL => '1',
                            .ARG => '2',
                            .This, .Pointer => '3',
                            .That => '4',
                            else => unreachable,
                        };
                        buf = try std.fmt.allocPrint(self.allocator, template, .{ index, pAddr });
                    },
                    else => {
                        const baseAddr = self.baseAddrTable.get(segment).?;
                        const addrOffset = baseAddr + index;

                        const output =
                            \\@SP
                            \\AM=M-1
                            \\D=M
                            \\@{d}
                            \\M=D
                        ;
                        buf = try std.fmt.allocPrint(self.allocator, output, .{addrOffset});
                    },
                }
            },
            else => {
                return;
            },
        }
        try self.instructions.append(self.allocator, buf);
    }

    pub fn close(self: *Self, io: std.Io) !void {
        const outputFile = try std.Io.Dir.cwd().createFile(io, self.outputPath, .{ .read = false });
        defer outputFile.close(io);

        const output = try mem.join(self.allocator, "\n", self.instructions.items);
        defer self.allocator.free(output);

        try outputFile.writeStreamingAll(io, output);
    }
};

test "smoke" {
    var cw = try CodeWriter.init(testing.io, testing.allocator);
    defer cw.deinit();

    try testing.expect(cw.instructions.items.len == 0);
}

test "writePushPop" {
    var cw = try CodeWriter.init(testing.io, testing.allocator);
    defer cw.deinit();

    try cw.writePushPop(.C_PUSH, .Constant, 10);
    try testing.expectEqual(cw.instructions.items.len, 1);
    try cw.writePushPop(.C_POP, .LCL, 0);
    try testing.expectEqual(cw.instructions.items.len, 2);

    for (cw.instructions.items) |item| {
        // While not worried about testing the instruction implementation,
        // POP/PUSH should have at least one reference to 'SP' and should
        // also be valid memory (i.e. not segfaulting on access)
        try testing.expect(mem.count(u8, item, "SP") > 0);
    }
}

test "writeArithmetic" {
    var cw = try CodeWriter.init(testing.io, testing.allocator);
    defer cw.deinit();

    try cw.writeArithmetic(.Add);
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "D+M") > 0);
    try cw.writeArithmetic(.Sub);
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "M-D") > 0);
    try cw.writeArithmetic(.And);
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "D&M") > 0);
    try cw.writeArithmetic(.Or);
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "D|M") > 0);
    try cw.writeArithmetic(.Neg);
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "-M") > 0);
    try cw.writeArithmetic(.Not);
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "!M") > 0);
    try cw.writeArithmetic(.Eq);
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "JEQ") > 0);
    try cw.writeArithmetic(.Lt);
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "JLT") > 0);
    try cw.writeArithmetic(.Gt);
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "JGT") > 0);
}

test "setFileName and close" {
    var cw = try CodeWriter.init(testing.io, testing.allocator);
    defer cw.deinit();

    const filename = "./test/test_output.asm";
    cw.setFileName(filename);
    try cw.writePushPop(.C_PUSH, .Constant, 42);
    try cw.writePushPop(.C_PUSH, .Constant, 27);
    try cw.writeArithmetic(.Add);
    try cw.close(testing.io);

    const file = try std.Io.Dir.cwd().openFile(testing.io, filename, .{ .mode = .read_only });
    defer file.close(testing.io);
    defer std.Io.Dir.cwd().deleteFile(testing.io, filename) catch {
        std.debug.print("Failed to delete test file: {s}\n", .{filename});
    };

    try testing.expect(try file.length(testing.io) > 0);
}

test "writeInit" {
    var cw = try CodeWriter.init(testing.io, testing.allocator);
    defer cw.deinit();

    try cw.writeInit();
    const instruction = cw.instructions.getLast().?;
    try testing.expect(mem.count(u8, instruction, "@0") > 0);
    try testing.expect(mem.count(u8, instruction, "@1") > 0);
    try testing.expect(mem.count(u8, instruction, "@2") > 0);
    try testing.expect(mem.count(u8, instruction, "@3") > 0);
}
