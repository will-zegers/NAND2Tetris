const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

const Self = @This();

allocator: Allocator,
map: StringHashMap([]const u8),

pub fn init(allocator: Allocator) !Self {
    var map = StringHashMap([]const u8).init(allocator);
    errdefer map.deinit();

    try map.put("M", "001");
    try map.put("D", "010");
    try map.put("MD", "011");
    try map.put("A", "100");
    try map.put("AM", "101");
    try map.put("AD", "110");
    try map.put("ADM", "111");

    return .{
        .allocator = allocator,
        .map = map,
    };
}

pub fn deinit(self: *Self) void {
    defer self.map.deinit();
}

pub fn get(self: Self, key: []const u8) []const u8 {
    return self.map.get(key) orelse {
        std.log.err("{any} Unrecognized dest: {s}", .{ Self, key });
        std.process.exit(1);
    };
}

test "smoke" {
    var map = try init(std.testing.allocator);
    defer map.deinit();
}
