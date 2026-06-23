const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const testing = std.testing;

const Self = @This();

pub const Type = enum {
    Add,
    Sub,
    And,
    Or,
    Neg,
    Not,
    Eq,
    Lt,
    Gt,
};

map: StringHashMap(Type),

pub fn init(allocator: Allocator) !Self {
    var map = StringHashMap(Type).init(allocator);
    errdefer map.deinit();

    try map.put("add", .Add);
    try map.put("sub", .Sub);
    try map.put("and", .And);
    try map.put("or", .Or);
    try map.put("neg", .Neg);
    try map.put("not", .Not);
    try map.put("eq", .Eq);
    try map.put("lt", .Lt);
    try map.put("gt", .Gt);

    return .{ .map = map };
}

pub fn deinit(self: *Self) void {
    self.map.deinit();
}

pub fn get(self: Self, key: []const u8) ?Type {
    return self.map.get(key);
}

test "smoke" {
    var map = try init(testing.allocator);
    defer map.deinit();
}
