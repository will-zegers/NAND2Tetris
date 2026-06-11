const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");

const COMP_FILE = "./table/comp.table";
const DEST_FILE = "./table/dest.table";
const JUMP_FILE = "./table/jump.table";

const BUFFER_SIZE = 1024;

pub const Code = struct {
    const Self = @This();

    compTable: std.StringHashMap([]const u8),
    destTable: std.StringHashMap([]const u8),
    jumpTable: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(io: std.Io, allocator: std.mem.Allocator) !Self {
        return Self{
            .compTable = try util.hashmapFromFile(COMP_FILE, ':', io, allocator),
            .destTable = try util.hashmapFromFile(DEST_FILE, ':', io, allocator),
            .jumpTable = try util.hashmapFromFile(JUMP_FILE, ':', io, allocator),
            .allocator = allocator,
        };
    }

    pub fn dest(self: Self, mnemonic: []const u8) ?[]const u8 {
        return self.destTable.get(mnemonic);
    }

    pub fn comp(self: Self, mnemonic: []const u8) ?[]const u8 {
        return self.compTable.get(mnemonic);
    }

    pub fn jump(self: Self, mnemonic: []const u8) ?[]const u8 {
        return self.jumpTable.get(mnemonic);
    }

    pub fn deinit(self: *Self) void {
        util.freeMap(&self.compTable, self.allocator);
        util.freeMap(&self.destTable, self.allocator);
        util.freeMap(&self.jumpTable, self.allocator);
    }
};

test "smoke" {
    var code = try Code.init(testing.io, testing.allocator);
    defer code.deinit();
}

test "comp" {
    var code = try Code.init(testing.io, testing.allocator);
    defer code.deinit();

    const comp = code.comp("D|M").?;
    try testing.expectEqualStrings(comp, "010101");
}

test "dest" {
    var code = try Code.init(testing.io, testing.allocator);
    defer code.deinit();

    const dest = code.dest("MD").?;
    try testing.expectEqualStrings(dest, "011");
}

test "jump" {
    var code = try Code.init(testing.io, testing.allocator);
    defer code.deinit();

    const jump = code.jump("JGT").?;
    try testing.expectEqualStrings(jump, "001");
}
