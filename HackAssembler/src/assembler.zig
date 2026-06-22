const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Io = std.Io;
const fmt = std.fmt;
const mem = std.mem;
const testing = std.testing;

const Code = @import("code.zig").Code;
const Parser = @import("parser.zig").Parser;
const SymbolTable = @import("map/symbol.zig").SymbolTable;

pub const Assembler = struct {
    const Self = @This();

    allocator: Allocator,
    parser: Parser,
    code: Code,
    symbolTable: SymbolTable,
    instructions: ArrayList([]const u8),
    outputPath: []const u8,

    pub fn init(inputFile: []const u8, outputPath: []const u8, io: Io, allocator: Allocator) !Self {
        return .{
            .allocator = allocator,
            .parser = try .init(inputFile, io, allocator),
            .code = try .init(allocator),
            .symbolTable = try .init(allocator),
            .instructions = try .initCapacity(allocator, 512),
            .outputPath = outputPath,
        };
    }

    pub fn deinit(self: *Self) void {
        defer self.code.deinit();
        defer self.parser.deinit();
        defer self.symbolTable.deinit();
        defer self.instructions.deinit(self.allocator);

        for (self.instructions.items) |item| {
            self.allocator.free(item);
        }
    }

    /// "AVENGERS...✪!!!"
    /// Caller owns the returned slice
    pub fn assemble(self: *Self) !void {
        try self.firstPass();
        try self.secondPass();
    }

    // First pass: resolve labels and build symbol table
    fn firstPass(self: *Self) !void {
        var pc: usize = 0;

        while (self.parser.hasMoreCommands()) {
            self.parser.advance();
            if (self.parser.commandType() == .L_COMMAND) {
                try self.symbolTable.put(self.parser.symbol().?, pc);
                continue;
            }
            pc += 1;
        }
    }

    // Second pass: translate to binary and resolve symbols
    fn secondPass(self: *Self) !void {
        var staticAddr: usize = 16;

        self.parser.reset();
        while (self.parser.hasMoreCommands()) {
            var buf: []u8 = undefined;

            self.parser.advance();
            switch (self.parser.commandType().?) {
                .L_COMMAND => continue,
                .A_COMMAND => {
                    const symbol = self.parser.symbol().?;
                    if (fmt.parseInt(usize, symbol, 10)) |addr| { // numeric address
                        buf = try fmt.allocPrint(self.allocator, "{b:0>16}", .{addr});
                    } else |_| { // non-numeric; either new RAM address, existing static, or existing ROM label
                        if (self.symbolTable.get(symbol)) |addr| { // existing symbol defined by a label
                            buf = try fmt.allocPrint(self.allocator, "{b:0>16}", .{addr});
                        } else { //new symbol, store as a static
                            buf = try fmt.allocPrint(self.allocator, "{b:0>16}", .{staticAddr});
                            try self.symbolTable.put(symbol, staticAddr);
                            staticAddr += 1;
                        }
                    }
                },
                .C_COMMAND => {
                    const compKey = self.parser.comp().?;
                    const comp = self.code.comp(compKey);
                    if (self.parser.dest()) |destKey| { // arithmetic operation
                        const aBit: u8 = if (mem.countScalar(u8, compKey, 'M') > 0) '1' else '0';
                        const dest = self.code.dest(destKey);
                        buf = try fmt.allocPrint(self.allocator, "111{c}{s}{s}000", .{ aBit, comp, dest });
                    } else if (self.parser.jump()) |jumpKey| { // jump operation
                        const jump = self.code.jump(jumpKey);
                        buf = try fmt.allocPrint(self.allocator, "1110{s}000{s}", .{ comp, jump });
                    }
                },
            }
            try self.instructions.append(self.allocator, buf);
        }
    }

    pub fn close(self: Self, io: Io) !void {
        const output = try mem.join(self.allocator, "\n", self.instructions.items);
        defer self.allocator.free(output);

        const outputFile = try Io.Dir.cwd().createFile(io, self.outputPath, .{ .read = false });
        defer outputFile.close(io);

        try outputFile.writeStreamingAll(io, output);
    }
};

const TEST_FILE: []const u8 = "./test/Rect.asm";

test "smoke" {
    var assembler = try Assembler.init(TEST_FILE, testing.io, testing.allocator);
    defer assembler.deinit();

    const out = try assembler.assemble(testing.allocator);
    defer testing.allocator.free(out);
}

test "firstPass" {
    var assembler = try Assembler.init(TEST_FILE, testing.io, testing.allocator);
    defer assembler.deinit();

    try testing.expectEqual(assembler.symbolTable.get("LOOP"), null);
    try testing.expectEqual(assembler.symbolTable.get("END"), null);
    try testing.expectEqual(assembler.symbolTable.get("addr"), null);

    try assembler.firstPass();
    try testing.expectEqual(assembler.symbolTable.get("LOOP"), 10);
    try testing.expectEqual(assembler.symbolTable.get("END"), 23);
    try testing.expectEqual(assembler.symbolTable.get("addr"), null);
}

test "secondPass and assemble" {
    var assembler = try Assembler.init(TEST_FILE, testing.io, testing.allocator);
    defer assembler.deinit();
    const output = try assembler.assemble(testing.allocator);
    defer testing.allocator.free(output);

    try testing.expectEqual(output.len, 424);
    try testing.expectEqualStrings("0000000000000000", assembler.instructions.items[0]);
    try testing.expectEqualStrings("0000000000010000", assembler.instructions.items[4]);
    try testing.expectEqualStrings("0000000000010001", assembler.instructions.items[8]);
    try testing.expectEqualStrings("1110111010001000", assembler.instructions.items[12]);
    try testing.expectEqualStrings("1110000010010000", assembler.instructions.items[16]);
    try testing.expectEqualStrings("1111110010011000", assembler.instructions.items[20]);
    try testing.expectEqualStrings("1110101010000111", assembler.instructions.items[24]);
}
