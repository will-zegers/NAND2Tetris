const std = @import("std");
const testing = std.testing;

const Code = @import("code.zig").Code;
const Parser = @import("parser.zig").Parser;
const SymbolTable = @import("symbol.zig").SymbolTable;
const util = @import("util.zig");

const BUFFER_SIZE: usize = 1 * 1024 * 1024; // 1 MiB

pub const Assembler = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    buffer: []u8,
    bufferLength: usize,
    code: Code,
    symbolTable: SymbolTable,

    pub fn init(asmPath: []const u8, io: std.Io, allocator: std.mem.Allocator) !Self {
        const buffer: []u8 = try allocator.alloc(u8, BUFFER_SIZE);
        errdefer allocator.free(buffer);

        const bufferLength = try util.readASMFile(asmPath, buffer, io);
        return Self{
            .allocator = allocator,
            .bufferLength = bufferLength,
            .buffer = buffer,
            .code = try Code.init(io, allocator),
            .symbolTable = try SymbolTable.init(io, allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buffer);
        self.code.deinit();
        self.symbolTable.deinit();
    }

    // "AVENGERS...✪!!!"
    pub fn assemble(self: *Self) ![]const u8 {
        try self.firstPass();
        try self.secondPass();

        return self.buffer[0 .. self.bufferLength - 1];
    }

    // First pass: resolve labels and build symbol table
    fn firstPass(self: *Self) !void {
        var pc: usize = 0;
        var length: usize = 0;
        var out: [BUFFER_SIZE]u8 = undefined;
        var parser = try Parser.init(self.buffer[0..self.bufferLength]);

        while (parser.hasMoreCommands()) {
            var buf: []u8 = undefined;

            parser.advance();
            if (parser.commandType() == .L_COMMAND) {
                try self.symbolTable.addEntry(parser.symbol().?, pc);
                continue;
            } else if (parser.symbol()) |symbol| {
                buf = try std.fmt.bufPrint(out[length..], "@{s}\n", .{symbol});
            } else {
                const comp = parser.comp().?;
                if (parser.dest()) |dest| {
                    buf = try std.fmt.bufPrint(out[length..], "{s}={s}\n", .{ dest, comp });
                } else if (parser.jump()) |jump| {
                    buf = try std.fmt.bufPrint(out[length..], "{s};{s}\n", .{ comp, jump });
                }
            }
            length += buf.len;
            pc += 1;
        }
        @memcpy(self.buffer, &out);
        self.bufferLength = length;
    }

    // Second pass: translate to binary and resolve symbols
    fn secondPass(self: *Self) !void {
        var length: usize = 0;
        var out: [BUFFER_SIZE]u8 = undefined;
        var parser = try Parser.init(self.buffer[0..self.bufferLength]);
        var ramAddr: usize = 0x10;

        while (parser.hasMoreCommands()) {
            var buf: []u8 = undefined;

            parser.advance();
            if (parser.symbol()) |symbol| {
                if (std.fmt.parseInt(u16, symbol, 10)) |addr| {
                    buf = try std.fmt.bufPrint(out[length..], "{b:0>16}\n", .{addr});
                } else |_| {
                    if (self.symbolTable.getAddress(symbol)) |addrStr| {
                        const addr = try std.fmt.parseInt(u16, addrStr, 10);
                        buf = try std.fmt.bufPrint(out[length..], "{b:0>16}\n", .{addr});
                    } else {
                        buf = try std.fmt.bufPrint(out[length..], "{b:0>16}\n", .{ramAddr});

                        try self.symbolTable.addEntry(symbol, ramAddr);
                        ramAddr += 1;
                    }
                }
            } else {
                const comp = parser.comp().?;
                if (parser.dest()) |dest| {
                    const aBit: u8 = if (util.contains(comp, 'M')) '1' else '0';
                    buf = try std.fmt.bufPrint(out[length..], "111{c}{s}{s}000\n", .{ aBit, self.code.comp(comp).?, self.code.dest(dest).? });
                } else if (parser.jump()) |jump| {
                    buf = try std.fmt.bufPrint(out[length..], "1110{s}000{s}\n", .{ self.code.comp(comp).?, self.code.jump(jump).? });
                }
            }
            length += buf.len;
        }
        @memcpy(self.buffer, &out);
        self.bufferLength = length;
    }
};

test "smoke" {
    var assembler = try Assembler.init("./test/Rect.asm", testing.io, testing.allocator);
    defer assembler.deinit();
}

test "firstPass" {
    var assembler = try Assembler.init("./test/Rect.asm", testing.io, testing.allocator);
    defer assembler.deinit();
    try std.testing.expect(std.mem.count(u8, assembler.buffer, "(LOOP)") > 0);
    try std.testing.expect(std.mem.count(u8, assembler.buffer, "(END)") > 0);
    try assembler.firstPass();
    try std.testing.expect(std.mem.count(u8, assembler.buffer, "(LOOP)") == 0);
    try std.testing.expect(std.mem.count(u8, assembler.buffer, "(END)") == 0);
    try std.testing.expect(assembler.symbolTable.contains("LOOP"));
    try std.testing.expect(assembler.symbolTable.contains("END"));
}

test "secondPass and assemble" {
    var assembler = try Assembler.init("./test/Rect.asm", testing.io, testing.allocator);
    defer assembler.deinit();
    const output = try assembler.assemble();

    try testing.expect(output.len == 424);
    try testing.expect(std.mem.eql(u8, "0000000000000000", assembler.buffer[0..16]));
    try testing.expect(std.mem.eql(u8, "0100000000000000", assembler.buffer[102..118]));
    try testing.expect(std.mem.eql(u8, "0000000000010001", assembler.buffer[221..237]));
    try testing.expect(std.mem.eql(u8, "0000000000100000", assembler.buffer[255..271]));
}
