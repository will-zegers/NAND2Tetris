const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const util = @import("util.zig");
const Parser = @import("parser.zig").Parser;
const CommandType = @import("parser.zig").CommandType;
const arithmetic = @import("arithmetic.zig");

const SYMBOL_FILE: []const u8 = "./table/vm_symbol.table";
const BASE_ADDR_TABLE: []const u8 = "./table/base_addr.table";

const CodeWriterError = error{UnrecognizedArithmeticCommand};

pub const CodeWriter = struct {
    const Self = @This();

    allocator: mem.Allocator,
    instructions: std.ArrayList([]const u8),
    baseAddrTable: std.StringHashMap([]const u8),
    symbolTable: std.StringHashMap([]const u8),
    outputPath: []const u8,

    pub fn init(io: std.Io, allocator: mem.Allocator) !Self {
        var baseAddrTable = try util.hashmapFromFile(BASE_ADDR_TABLE, ':', io, allocator);
        errdefer util.freeMap(&baseAddrTable, allocator);

        var symbolTable = try util.hashmapFromFile(SYMBOL_FILE, ':', io, allocator);
        errdefer util.freeMap(&symbolTable, allocator);

        return Self{
            .allocator = allocator,
            .instructions = try .initCapacity(allocator, 512),
            .symbolTable = symbolTable,
            .baseAddrTable = baseAddrTable,
            .outputPath = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.instructions.items) |item| {
            self.allocator.free(item);
        }
        defer self.instructions.deinit(self.allocator);
        defer util.freeMap(&self.symbolTable, self.allocator);
        defer util.freeMap(&self.baseAddrTable, self.allocator);
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

    pub fn writeArithmetic(self: *Self, operation: []const u8) !void {
        var buf: []const u8 = undefined;

        if (mem.eql(u8, "add", operation)) {
            buf = try arithmetic.Add.fmt(self.allocator);
        } else if (mem.eql(u8, "sub", operation)) {
            buf = try arithmetic.Sub.fmt(self.allocator);
        } else if (mem.eql(u8, "or", operation)) {
            buf = try arithmetic.Or.fmt(self.allocator);
        } else if (mem.eql(u8, "and", operation)) {
            buf = try arithmetic.And.fmt(self.allocator);
        } else if (mem.eql(u8, "neg", operation)) {
            buf = try arithmetic.Neg.fmt(self.allocator);
        } else if (mem.eql(u8, "not", operation)) {
            buf = try arithmetic.Not.fmt(self.allocator);
        } else if (mem.eql(u8, "eq", operation)) {
            buf = try arithmetic.EQ.fmt(self.allocator);
        } else if (mem.eql(u8, "lt", operation)) {
            buf = try arithmetic.LT.fmt(self.allocator);
        } else if (mem.eql(u8, "gt", operation)) {
            buf = try arithmetic.GT.fmt(self.allocator);
        } else {
            return CodeWriterError.UnrecognizedArithmeticCommand;
        }
        try self.instructions.append(self.allocator, buf);
    }

    pub fn writePushPop(self: *Self, commandType: CommandType, location: []const u8, index: []const u8) !void {
        const symbol = self.symbolTable.get(location).?;

        const baseAddr = self.baseAddrTable.get(symbol).?;
        const addrOffset = try std.fmt.parseInt(usize, baseAddr, 10) + try std.fmt.parseInt(usize, index, 10);

        var buf: []u8 = undefined;
        switch (commandType) {
            .C_PUSH => {
                if (mem.eql(u8, "THIS", symbol) or mem.eql(u8, "THAT", symbol) or mem.eql(u8, "LOCAL", symbol) or mem.eql(u8, "ARGUMENT", symbol)) {
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
                    const pAddr: u8 = if (mem.eql(u8, "THIS", symbol)) '3' else '4';
                    buf = try std.fmt.allocPrint(self.allocator, template, .{ index, pAddr });
                } else {
                    const template =
                        \\@{d}
                        \\D={c}
                        \\@SP
                        \\A=M
                        \\M=D
                        \\@SP
                        \\M=M+1
                    ;
                    const source: u8 = if (mem.eql(u8, "CONSTANT", symbol)) 'A' else 'M';
                    buf = try std.fmt.allocPrint(self.allocator, template, .{ addrOffset, source });
                }
            },
            .C_POP => {
                if (mem.eql(u8, "THIS", symbol) or mem.eql(u8, "THAT", symbol)) {
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
                    const pAddr: u8 = if (mem.eql(u8, "THIS", symbol)) '3' else '4';
                    buf = try std.fmt.allocPrint(self.allocator, template, .{ index, pAddr });
                } else {
                    const output =
                        \\@SP
                        \\AM=M-1
                        \\D=M
                        \\@{d}
                        \\M=D
                    ;
                    buf = try std.fmt.allocPrint(self.allocator, output, .{addrOffset});
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

    try cw.writePushPop(.C_PUSH, "constant", "10");
    try testing.expectEqual(cw.instructions.items.len, 1);
    try cw.writePushPop(.C_POP, "local", "0");
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

    try cw.writeArithmetic("add");
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "D+M") > 0);
    try cw.writeArithmetic("sub");
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "M-D") > 0);
    try cw.writeArithmetic("or");
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "D|M") > 0);
    try cw.writeArithmetic("and");
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "D&M") > 0);
    try cw.writeArithmetic("neg");
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "-M") > 0);
    try cw.writeArithmetic("not");
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "!M") > 0);
    try cw.writeArithmetic("eq");
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "JEQ") > 0);
    try cw.writeArithmetic("lt");
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "JLT") > 0);
    try cw.writeArithmetic("gt");
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "JGT") > 0);
}

test "setFileName and close" {
    var cw = try CodeWriter.init(testing.io, testing.allocator);
    defer cw.deinit();

    const filename = "./test/test_output.asm";
    cw.setFileName(filename);
    try cw.writePushPop(.C_PUSH, "constant", "42");
    try cw.writePushPop(.C_PUSH, "constant", "27");
    try cw.writeArithmetic("add");
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
