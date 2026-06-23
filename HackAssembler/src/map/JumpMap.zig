const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const process = std.process;
const testing = std.testing;

const Self = @This();

allocator: Allocator,
map: StringHashMap([]const u8),

pub fn init(allocator: Allocator) !Self {
    var map = StringHashMap([]const u8).init(allocator);
    errdefer map.deinit();

    try map.put("JGT", "001");
    try map.put("JEQ", "010");
    try map.put("JGE", "011");
    try map.put("JLT", "100");
    try map.put("JNE", "101");
    try map.put("JLE", "110");
    try map.put("JMP", "111");

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
        process.fatal("{any}: Unrecognized jump: {s}\n", .{ Self, key });
    };
}

test "smoke" {
    var map = try init(testing.allocator);
    defer map.deinit();
}
