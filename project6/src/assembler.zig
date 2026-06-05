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
    buffer_length: usize,
    code: Code,
    symbol_table: SymbolTable,

    pub fn init(asm_path: []const u8, io: std.Io, allocator: std.mem.Allocator) !Self {
        const buffer: []u8 = try allocator.alloc(u8, BUFFER_SIZE);
        const buffer_length = try util.readASMFile(asm_path, buffer, io);
        return Self{
            .allocator = allocator,
            .buffer_length = buffer_length,
            .buffer = buffer,
            .code = try Code.init(io, allocator),
            .symbol_table = try SymbolTable.init(io, allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buffer);
        self.code.deinit();
        self.symbol_table.deinit();
    }

    // "AVENGERS...✪!!!"
    pub fn assemble(self: *Self) ![]const u8 {
        try self.firstPass();
        try self.secondPass();

        return self.buffer[0 .. self.buffer_length - 1];
    }

    // First pass: resolve labels and build symbol table
    fn firstPass(self: *Self) !void {
        var pc: usize = 0;
        var length: usize = 0;
        var out: [BUFFER_SIZE]u8 = undefined;
        var parser = try Parser.init(self.buffer[0..self.buffer_length]);

        while (parser.hasMoreCommands()) {
            var buf: []u8 = undefined;

            parser.advance();
            if (parser.commandType() == .L_COMMAND) {
                try self.symbol_table.addEntry(parser.symbol().?, pc);
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
        self.buffer_length = length;
    }

    // Second pass: translate to binary and resolve symbols
    fn secondPass(self: *Self) !void {
        var length: usize = 0;
        var out: [BUFFER_SIZE]u8 = undefined;
        var parser = try Parser.init(self.buffer[0..self.buffer_length]);
        var ram_addr: usize = 0x10;

        while (parser.hasMoreCommands()) {
            var buf: []u8 = undefined;

            parser.advance();
            if (parser.symbol()) |symbol| {
                if (std.fmt.parseInt(u16, symbol, 10)) |addr| {
                    buf = try std.fmt.bufPrint(out[length..], "{b:0>16}\n", .{addr});
                } else |_| {
                    if (self.symbol_table.getAddress(symbol)) |addr_str| {
                        const addr = try std.fmt.parseInt(u16, addr_str, 10);
                        buf = try std.fmt.bufPrint(out[length..], "{b:0>16}\n", .{addr});
                    } else {
                        buf = try std.fmt.bufPrint(out[length..], "{b:0>16}\n", .{ram_addr});

                        try self.symbol_table.addEntry(symbol, ram_addr);
                        ram_addr += 1;
                    }
                }
            } else {
                const comp = parser.comp().?;
                if (parser.dest()) |dest| {
                    const a_bit: u8 = if (util.contains(comp, 'M')) '1' else '0';
                    buf = try std.fmt.bufPrint(out[length..], "111{c}{s}{s}000\n", .{ a_bit, self.code.comp(comp).?, self.code.dest(dest).? });
                } else if (parser.jump()) |jump| {
                    buf = try std.fmt.bufPrint(out[length..], "1110{s}000{s}\n", .{ self.code.comp(comp).?, self.code.jump(jump).? });
                }
            }
            length += buf.len;
        }
        @memcpy(self.buffer, &out);
        self.buffer_length = length;
    }
};

test "smoke" {
    var assembler = try Assembler.init("./test/Test.asm", testing.io, testing.allocator);
    defer assembler.deinit();
}

test "firstPass" {
    var assembler = try Assembler.init("./test/Test.asm", testing.io, testing.allocator);
    defer assembler.deinit();
    try std.testing.expect(std.mem.count(u8, assembler.buffer, "(LOOP)") > 0);
    try std.testing.expect(std.mem.count(u8, assembler.buffer, "(END)") > 0);
    try assembler.firstPass();
    try std.testing.expect(std.mem.count(u8, assembler.buffer, "(LOOP)") == 0);
    try std.testing.expect(std.mem.count(u8, assembler.buffer, "(END)") == 0);
    try std.testing.expect(assembler.symbol_table.contains("LOOP"));
    try std.testing.expect(assembler.symbol_table.contains("END"));
}

test "secondPass and assemble" {
    var assembler = try Assembler.init("./test/Test.asm", testing.io, testing.allocator);
    defer assembler.deinit();
    const output = try assembler.assemble();

    try testing.expect(output.len == 424);
    try testing.expect(std.mem.eql(u8, "0000000000000000", assembler.buffer[0..16]));
    try testing.expect(std.mem.eql(u8, "0100000000000000", assembler.buffer[102..118]));
    try testing.expect(std.mem.eql(u8, "0000000000010001", assembler.buffer[221..237]));
    try testing.expect(std.mem.eql(u8, "0000000000100000", assembler.buffer[255..271]));
}
