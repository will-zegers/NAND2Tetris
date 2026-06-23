const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const testing = std.testing;

const CompMap = @import("map/CompMap.zig");
const DestMap = @import("map/DestMap.zig");
const JumpMap = @import("map/JumpMap.zig");

const Self = @This();

allocator: Allocator,
compTable: CompMap,
destTable: DestMap,
jumpTable: JumpMap,

pub fn init(allocator: Allocator) !Self {
    return .{
        .allocator = allocator,
        .compTable = try .init(allocator),
        .destTable = try .init(allocator),
        .jumpTable = try .init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.compTable.deinit();
    self.destTable.deinit();
    self.jumpTable.deinit();
}

pub fn dest(self: Self, key: []const u8) []const u8 {
    return self.destTable.get(key);
}

pub fn comp(self: Self, key: []const u8) []const u8 {
    return self.compTable.get(key);
}

pub fn jump(self: Self, key: []const u8) []const u8 {
    return self.jumpTable.get(key);
}

test "smoke" {
    var code = try init(testing.allocator);
    defer code.deinit();
}

test "comp" {
    var code = try init(testing.allocator);
    defer code.deinit();

    const _comp = code.comp("D|M");
    try testing.expectEqualStrings(_comp, "010101");
}

test "dest" {
    var code = try init(testing.allocator);
    defer code.deinit();

    const _dest = code.dest("MD");
    try testing.expectEqualStrings(_dest, "011");
}

test "jump" {
    var code = try init(testing.allocator);
    defer code.deinit();

    const _jump = code.jump("JGT");
    try testing.expectEqualStrings(_jump, "001");
}
