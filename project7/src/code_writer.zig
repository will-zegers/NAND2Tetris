const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const util = @import("util.zig");
const Parser = @import("parser.zig").Parser;

const SYMBOL_FILE: []const u8 = "./table/vm_symbol.table";
const STACK_BASE: usize = 2047;
const BUFFER_SIZE: usize = 5 * 1024 * 1024;
const BASE_ADDR_TABLE: []const u8 = "./table/base_addr.table";

pub const CodeWriter = struct {
    const Self = @This();

    outputFile: ?std.Io.File,
    allocator: mem.Allocator,
    symbolTable: std.StringHashMap([]const u8),
    baseAddrTable: std.StringHashMap([]const u8),
    buffer: []u8,
    bufferLength: usize,
    parser: Parser,

    pub fn init(filepath: []const u8, io: std.Io, allocator: mem.Allocator) !Self {
        const buffer: []u8 = try allocator.alloc(u8, BUFFER_SIZE);
        return Self{
            .outputFile = null,
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

    // fn setFileName(fileName: []const u8) !void {
    //     var it = mem.splitScalar(u8, fileName, '.');
    //     const baseName = it.first;

    //     const cwd = std.Io.Dir.cwd();
    //     const outputPath = std.fmt.allocPrint(init.gpa, "{s}.asm", .{baseName});
    //     defer init.gpa.free(outputPath);
    //     const outputFile = try cwd.createFile(init.io, outputPath, .{ .read = false });
    // }

    pub fn writeArithmetic(self: *Self) !void {
        var op: []const u8 = undefined;
        switch (self.parser.commandType().?) {
            .C_ARITHMETIC => {
                const output =
                    \\@SP
                    \\AM=M-1
                    \\D=M
                    \\A=A-1
                    \\M={s}
                    \\
                ;
                const arg0 = self.parser.arg0().?;
                if (std.mem.eql(u8, "add", arg0)) {
                    op = "D+M";
                } else if (std.mem.eql(u8, "sub", arg0)) {
                    op = "M-D";
                }
                const buf = try std.fmt.bufPrint(self.buffer[self.bufferLength..], output, .{op});
                self.bufferLength += buf.len;
            },
            else => {
                return;
            },
        }
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

    pub fn writePushPop(self: *Self) !void {
        const location = self.parser.arg1().?;
        const value = self.parser.arg2().?;
        const symbol = self.symbolTable.get(location).?;
        switch (self.parser.commandType().?) {
            .C_PUSH => {
                if (std.mem.eql(u8, "constant", location)) {
                    const output =
                        \\@{s}
                        \\D=A
                        \\@SP
                        \\A=M
                        \\M=D
                        \\@SP
                        \\M=M+1
                        \\
                    ;
                    const buf = try std.fmt.bufPrint(self.buffer[self.bufferLength..], output, .{value});
                    self.bufferLength += buf.len;
                } else {
                    const baseAddr = self.baseAddrTable.get(symbol).?;
                    const resolvedAddr = try std.fmt.parseInt(usize, baseAddr, 10) + try std.fmt.parseInt(usize, value, 10);
                    const output =
                        \\@{d}
                        \\D=M
                        \\@SP
                        \\A=M
                        \\M=D
                        \\@SP
                        \\M=M+1
                        \\
                    ;
                    const buf = try std.fmt.bufPrint(self.buffer[self.bufferLength..], output, .{resolvedAddr});
                    self.bufferLength += buf.len;
                }
            },
            .C_POP => {
                const baseAddr = self.baseAddrTable.get(symbol).?;
                const resolvedAddr = try std.fmt.parseInt(usize, baseAddr, 10) + try std.fmt.parseInt(usize, value, 10);
                const output =
                    \\@SP
                    \\AM=M-1
                    \\D=M
                    \\@{d}
                    \\M=D
                    \\
                ;
                const buf = try std.fmt.bufPrint(self.buffer[self.bufferLength..], output, .{resolvedAddr});
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
