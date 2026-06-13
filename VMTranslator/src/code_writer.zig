const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const AutoHashMap = std.AutoHashMap;

const util = @import("util.zig");
const CommandType = @import("parser.zig").CommandType;
const arithmetic = @import("arithmetic.zig");
const ArithmeticOperation = @import("parser.zig").ArithmeticOperation;
const Segment = @import("parser.zig").Segment;

const SYMBOL_FILE: []const u8 = "./table/vm_symbol.table";
const BASE_ADDR_TABLE: []const u8 = "./table/base_addr.table";

const CodeWriterError = error{UnrecognizedArithmeticCommand};

const BaseAddressMap = struct {
    const Self = @This();

    map: AutoHashMap(Segment, u16),

    pub fn init(allocator: mem.Allocator) !Self {
        var map = AutoHashMap(Segment, u16).init(allocator);
        errdefer map.deinit();

        try map.put(.Constant, 0);
        try map.put(.Temp, 5);
        try map.put(.Static, 16);

        return Self{ .map = map };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
    }

    pub fn get(self: Self, key: Segment) ?u16 {
        return self.map.get(key);
    }
};

pub const CodeWriter = struct {
    const Self = @This();

    allocator: mem.Allocator,
    instructions: std.ArrayList([]const u8),
    baseAddrTable: BaseAddressMap,
    outputPath: []const u8,

    pub fn init(allocator: mem.Allocator) !Self {
        var baseAddrTable = try BaseAddressMap.init(allocator);
        errdefer baseAddrTable.deinit();

        return Self{
            .allocator = allocator,
            .instructions = try .initCapacity(allocator, 512),
            .baseAddrTable = baseAddrTable,
            .outputPath = undefined,
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

    pub fn writeArithmetic(self: *Self, operation: ArithmeticOperation) !void {
        const buf: []const u8 = switch (operation) {
            .Add => try arithmetic.Add.fmt(self.allocator),
            .Sub => try arithmetic.Sub.fmt(self.allocator),
            .And => try arithmetic.And.fmt(self.allocator),
            .Or => try arithmetic.Or.fmt(self.allocator),
            .Neg => try arithmetic.Neg.fmt(self.allocator),
            .Not => try arithmetic.Not.fmt(self.allocator),
            .Eq => try arithmetic.EQ.fmt(self.allocator),
            .Lt => try arithmetic.LT.fmt(self.allocator),
            .Gt => try arithmetic.GT.fmt(self.allocator),
        };

        try self.instructions.append(self.allocator, buf);
    }

    pub fn writePushPop(self: *Self, commandType: CommandType, segment: Segment, index: []const u8) !void {
        var buf: []u8 = undefined;
        switch (commandType) {
            .C_PUSH => {
                switch (segment) {
                    .LCL, .ARG, .This, .That, .Pointer => {
                        const template =
                            \\@{s}
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
                        const addrOffset = baseAddr + try std.fmt.parseInt(usize, index, 10);

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
                            \\@{s}
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
                        const addrOffset = baseAddr + try std.fmt.parseInt(usize, index, 10);

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
    var cw = try CodeWriter.init(testing.allocator);
    defer cw.deinit();

    try testing.expect(cw.instructions.items.len == 0);
}

test "writePushPop" {
    var cw = try CodeWriter.init(testing.allocator);
    defer cw.deinit();

    try cw.writePushPop(.C_PUSH, .Constant, "10");
    try testing.expectEqual(cw.instructions.items.len, 1);
    try cw.writePushPop(.C_POP, .LCL, "0");
    try testing.expectEqual(cw.instructions.items.len, 2);

    for (cw.instructions.items) |item| {
        // While not worried about testing the instruction implementation,
        // POP/PUSH should have at least one reference to 'SP' and should
        // also be valid memory (i.e. not segfaulting on access)
        try testing.expect(mem.count(u8, item, "SP") > 0);
    }
}

test "writeArithmetic" {
    var cw = try CodeWriter.init(testing.allocator);
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
    var cw = try CodeWriter.init(testing.allocator);
    defer cw.deinit();

    const filename = "./test/test_output.asm";
    cw.setFileName(filename);
    try cw.writePushPop(.C_PUSH, .Constant, "42");
    try cw.writePushPop(.C_PUSH, .Constant, "27");
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
    var cw = try CodeWriter.init(testing.allocator);
    defer cw.deinit();

    try cw.writeInit();
    const instruction = cw.instructions.getLast().?;
    try testing.expect(mem.count(u8, instruction, "@0") > 0);
    try testing.expect(mem.count(u8, instruction, "@1") > 0);
    try testing.expect(mem.count(u8, instruction, "@2") > 0);
    try testing.expect(mem.count(u8, instruction, "@3") > 0);
}
