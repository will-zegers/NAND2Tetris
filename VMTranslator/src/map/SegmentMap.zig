const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const testing = std.testing;

pub const Type = enum {
    Local,
    Argument,
    Pointer,
    This,
    That,
    Temp,
    Static,
    Constant,
};

const Self = @This();

map: StringHashMap(Type),

pub fn init(allocator: Allocator) !Self {
    var map = StringHashMap(Type).init(allocator);
    errdefer map.deinit();

    try map.put("local", .Local);
    try map.put("argument", .Argument);
    try map.put("pointer", .Pointer);
    try map.put("this", .This);
    try map.put("that", .That);
    try map.put("temp", .Temp);
    try map.put("static", .Static);
    try map.put("constant", .Constant);

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
