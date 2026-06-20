const std = @import("std");
const testing = std.testing;

const CompTable = @import("map/comp.zig").CompTable;
const DestTable = @import("map/dest.zig").DestTable;
const JumpTable = @import("map/jump.zig").JumpTable;

pub const Code = struct {
    const Self = @This();

    compTable: CompTable,
    destTable: DestTable,
    jumpTable: JumpTable,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .compTable = try .init(allocator),
            .destTable = try .init(allocator),
            .jumpTable = try .init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.compTable.deinit();
        self.destTable.deinit();
        self.jumpTable.deinit();
    }

    pub fn dest(self: Self, key: []const u8) ?[]const u8 {
        return self.destTable.get(key);
    }

    pub fn comp(self: Self, key: []const u8) ?[]const u8 {
        return self.compTable.get(key);
    }

    pub fn jump(self: Self, key: []const u8) ?[]const u8 {
        return self.jumpTable.get(key);
    }
};

test "smoke" {
    var code = try Code.init(testing.allocator);
    defer code.deinit();
}

test "comp" {
    var code = try Code.init(testing.allocator);
    defer code.deinit();

    const comp = code.comp("D|M").?;
    try testing.expectEqualStrings(comp, "010101");
}

test "dest" {
    var code = try Code.init(testing.allocator);
    defer code.deinit();

    const dest = code.dest("MD").?;
    try testing.expectEqualStrings(dest, "011");
}

test "jump" {
    var code = try Code.init(testing.allocator);
    defer code.deinit();

    const jump = code.jump("JGT").?;
    try testing.expectEqualStrings(jump, "001");
}
