const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const util = @import("util.zig");
const Parser = @import("parser.zig").Parser;
const arithmetic = @import("arithmetic.zig");

const SYMBOL_FILE: []const u8 = "./table/vm_symbol.table";
const STACK_BASE: usize = 2047;
const BUFFER_SIZE: usize = 5 * 1024 * 1024;
const BASE_ADDR_TABLE: []const u8 = "./table/base_addr.table";

pub const CodeWriter = struct {
    const Self = @This();

    allocator: mem.Allocator,
    symbolTable: std.StringHashMap([]const u8),
    baseAddrTable: std.StringHashMap([]const u8),
    buffer: []u8,
    bufferLength: usize,
    parser: Parser,

    pub fn init(filepath: []const u8, io: std.Io, allocator: mem.Allocator) !Self {
        const buffer: []u8 = try allocator.alloc(u8, BUFFER_SIZE);
        return Self{
            .allocator = allocator,
            .buffer = buffer,
            .symbolTable = try util.hashmapFromFile(SYMBOL_FILE, ':', io, allocator),
            .baseAddrTable = try util.hashmapFromFile(BASE_ADDR_TABLE, ':', io, allocator),
            .bufferLength = 0,
            .parser = try Parser.init(filepath, io, allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        defer self.allocator.free(self.buffer);
        defer self.parser.deinit();
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
        return self.buffer[0..self.bufferLength];
    }

    pub fn writeArithmetic(self: *Self) !void {
        const command = self.parser.arg0().?;
        var buf: []const u8 = undefined;
        if (mem.eql(u8, "add", command)) {
            buf = try arithmetic.Add.fmt(self.buffer[self.bufferLength..]);
        } else if (mem.eql(u8, "sub", command)) {
            buf = try arithmetic.Sub.fmt(self.buffer[self.bufferLength..]);
        } else if (mem.eql(u8, "or", command)) {
            buf = try arithmetic.Or.fmt(self.buffer[self.bufferLength..]);
        } else if (mem.eql(u8, "and", command)) {
            buf = try arithmetic.And.fmt(self.buffer[self.bufferLength..]);
        } else if (mem.eql(u8, "neg", command)) {
            buf = try arithmetic.Neg.fmt(self.buffer[self.bufferLength..]);
        } else if (mem.eql(u8, "not", command)) {
            buf = try arithmetic.Not.fmt(self.buffer[self.bufferLength..]);
        } else if (mem.eql(u8, "eq", command)) {
            buf = try arithmetic.EQ.fmt(self.buffer[self.bufferLength..]);
        } else if (mem.eql(u8, "lt", command)) {
            buf = try arithmetic.LT.fmt(self.buffer[self.bufferLength..]);
        } else if (mem.eql(u8, "gt", command)) {
            buf = try arithmetic.GT.fmt(self.buffer[self.bufferLength..]);
        } else {
            std.process.fatal("Unknown arithmetic command: {s}\n", .{command});
        }
        self.bufferLength += buf.len;
    }

    pub fn writePushPop(self: *Self) !void {
        const location = self.parser.arg1().?;
        const value = self.parser.arg2().?;
        const symbol = self.symbolTable.get(location).?;

        const baseAddr = self.baseAddrTable.get(symbol).?;
        const addrOffset = try std.fmt.parseInt(usize, baseAddr, 10) + try std.fmt.parseInt(usize, value, 10);
        switch (self.parser.commandType().?) {
            .C_PUSH => {
                const output =
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
                const buf = try std.fmt.bufPrint(self.buffer[self.bufferLength..], output, .{ addrOffset, source });
                self.bufferLength += buf.len;
            },
            .C_POP => {
                const output =
                    \\@SP
                    \\AM=M-1
                    \\D=M
                    \\@{d}
                    \\M=D
                    \\
                ;
                const buf = try std.fmt.bufPrint(self.buffer[self.bufferLength..], output, .{addrOffset});
                self.bufferLength += buf.len;
            },
            else => {
                return;
            },
        }
    }
};

test "smoke" {
    var codeWriter = try CodeWriter.init("./test/Test.vm", testing.io, testing.allocator);
    defer codeWriter.deinit();
}

test "writePushPop" {
    var codeWriter = try CodeWriter.init("./test/Test.vm", testing.io, testing.allocator);
    defer codeWriter.deinit();

    _ = try codeWriter.run();
}
