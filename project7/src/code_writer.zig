const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const util = @import("util.zig");
const Parser = @import("parser.zig").Parser;
const arithmetic = @import("arithmetic.zig");

const SYMBOL_FILE: []const u8 = "./table/vm_symbol.table";
const BASE_ADDR_TABLE: []const u8 = "./table/base_addr.table";

pub const CodeWriter = struct {
    const Self = @This();

    allocator: mem.Allocator,
    parser: Parser,
    instructions: std.ArrayList(u8),
    baseAddrTable: std.StringHashMap([]const u8),
    symbolTable: std.StringHashMap([]const u8),

    pub fn init(filepath: []const u8, io: std.Io, allocator: mem.Allocator) !Self {
        var parser = try Parser.init(filepath, io, allocator);
        errdefer parser.deinit();

        var baseAddrTable = try util.hashmapFromFile(BASE_ADDR_TABLE, ':', io, allocator);
        errdefer util.freeMap(&baseAddrTable, allocator);

        var symbolTable = try util.hashmapFromFile(SYMBOL_FILE, ':', io, allocator);
        errdefer util.freeMap(&symbolTable, allocator);

        return Self{
            .allocator = allocator,
            .instructions = try .initCapacity(allocator, 1024),
            .parser = parser,
            .symbolTable = symbolTable,
            .baseAddrTable = baseAddrTable,
        };
    }

    pub fn deinit(self: *Self) void {
        defer self.parser.deinit();
        defer self.instructions.deinit(self.allocator);
        defer util.freeMap(&self.symbolTable, self.allocator);
        defer util.freeMap(&self.baseAddrTable, self.allocator);
    }

    pub fn run(self: *Self) ![]u8 {
        while (self.parser.hasMoreCommands()) {
            self.parser.advance();
            if (self.parser.commandType() == .C_PUSH or self.parser.commandType() == .C_POP) {
                try self.writePushPop();
            } else {
                try self.writeArithmetic();
            }
        }
        return self.instructions.items;
    }

    pub fn writeArithmetic(self: *Self) !void {
        const command = self.parser.arg0().?;
        var buf: []const u8 = undefined;
        defer self.allocator.free(buf);
        if (mem.eql(u8, "add", command)) {
            buf = try arithmetic.Add.fmt(self.allocator);
        } else if (mem.eql(u8, "sub", command)) {
            buf = try arithmetic.Sub.fmt(self.allocator);
        } else if (mem.eql(u8, "or", command)) {
            buf = try arithmetic.Or.fmt(self.allocator);
        } else if (mem.eql(u8, "and", command)) {
            buf = try arithmetic.And.fmt(self.allocator);
        } else if (mem.eql(u8, "neg", command)) {
            buf = try arithmetic.Neg.fmt(self.allocator);
        } else if (mem.eql(u8, "not", command)) {
            buf = try arithmetic.Not.fmt(self.allocator);
        } else if (mem.eql(u8, "eq", command)) {
            buf = try arithmetic.EQ.fmt(self.allocator);
        } else if (mem.eql(u8, "lt", command)) {
            buf = try arithmetic.LT.fmt(self.allocator);
        } else if (mem.eql(u8, "gt", command)) {
            buf = try arithmetic.GT.fmt(self.allocator);
        } else {
            std.process.fatal("Unknown arithmetic command: {s}\n", .{command});
        }
        try self.instructions.appendSlice(self.allocator, buf);
    }

    pub fn writePushPop(self: *Self) !void {
        const location = self.parser.arg1().?;
        const value = self.parser.arg2().?;
        const symbol = self.symbolTable.get(location).?;

        const baseAddr = self.baseAddrTable.get(symbol).?;
        const addrOffset = try std.fmt.parseInt(usize, baseAddr, 10) + try std.fmt.parseInt(usize, value, 10);

        var buf: []u8 = undefined;
        defer self.allocator.free(buf);
        switch (self.parser.commandType().?) {
            .C_PUSH => {
                if (mem.eql(u8, "THIS", symbol) or (mem.eql(u8, "THAT", symbol))) {
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
                        \\
                    ;
                    const pAddr: u8 = if (mem.eql(u8, "THIS", symbol)) '3' else '4';
                    buf = try std.fmt.allocPrint(self.allocator, template, .{ value, pAddr });
                } else {
                    const template =
                        \\@{d}
                        \\D={c}
                        \\@SP
                        \\A=M
                        \\M=D
                        \\@SP
                        \\M=M+1
                        \\
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
                        \\
                    ;
                    const pAddr: u8 = if (mem.eql(u8, "THIS", symbol)) '3' else '4';
                    buf = try std.fmt.allocPrint(self.allocator, template, .{ value, pAddr });
                } else {
                    const output =
                        \\@SP
                        \\AM=M-1
                        \\D=M
                        \\@{d}
                        \\M=D
                        \\
                    ;
                    buf = try std.fmt.allocPrint(self.allocator, output, .{addrOffset});
                }
            },
            else => {
                return;
            },
        }
        try self.instructions.appendSlice(self.allocator, buf);
    }
};

test "smoke" {
    var codeWriter = try CodeWriter.init("./test/BasicTest.vm", testing.io, testing.allocator);
    defer codeWriter.deinit();
}

test "writePushPop" {
    var codeWriter = try CodeWriter.init("./test/BasicTest.vm", testing.io, testing.allocator);
    defer codeWriter.deinit();

    _ = try codeWriter.run();
}
