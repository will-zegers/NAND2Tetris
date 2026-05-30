const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");

const COMP_FILE = "./table/comp.table";
const DEST_FILE = "./table/dest.table";
const JUMP_FILE = "./table/jump.table";

const BUFFER_SIZE = 1024;

pub fn Code() type {
    return struct {
        const Self = @This();

        comp_table: std.StringHashMap([]const u8),
        dest_table: std.StringHashMap([]const u8),
        jump_table: std.StringHashMap([]const u8),
        allocator: std.mem.Allocator,

        pub fn init(io: std.Io, allocator: std.mem.Allocator) !Self {
            return Self{
                .comp_table = try util.hashmap_from_file(COMP_FILE, ':', io, allocator),
                .dest_table = try util.hashmap_from_file(DEST_FILE, ':', io, allocator),
                .jump_table = try util.hashmap_from_file(JUMP_FILE, ':', io, allocator),
                .allocator = allocator,
            };
        }

        pub fn dest(self: Self, mnemonic: []const u8) ?[]const u8 {
            return self.dest_table.get(mnemonic);
        }

        pub fn comp(self: Self, mnemonic: []const u8) ?[]const u8 {
            return self.comp_table.get(mnemonic);
        }

        pub fn jump(self: Self, mnemonic: []const u8) ?[]const u8 {
            return self.jump_table.get(mnemonic);
        }

        pub fn deinit(self: *Self) void {
            util.freeMap(&self.comp_table, self.allocator);
            util.freeMap(&self.dest_table, self.allocator);
            util.freeMap(&self.jump_table, self.allocator);
        }
    };
}

test "init" {
    var code = try Code().init(testing.io, testing.allocator);
    defer code.deinit();
}

test "comp" {
    var code = try Code().init(testing.io, testing.allocator);
    defer code.deinit();

    const comp = code.comp("D|M").?;
    try testing.expectEqualStrings(comp, "010101");
}

test "dest" {
    var code = try Code().init(testing.io, testing.allocator);
    defer code.deinit();

    const dest = code.dest("MD").?;
    try testing.expectEqualStrings(dest, "011");
}

test "jump" {
    var code = try Code().init(testing.io, testing.allocator);
    defer code.deinit();

    const jump = code.jump("JGT").?;
    try testing.expectEqualStrings(jump, "001");
}
