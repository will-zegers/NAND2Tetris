const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

const Self = @This();

allocator: Allocator,
map: StringHashMap([]const u8),

pub fn init(allocator: Allocator) !Self {
    var map = StringHashMap([]const u8).init(allocator);
    errdefer map.deinit();

    try map.put("0", "101010");
    try map.put("1", "111111");
    try map.put("-1", "111010");
    try map.put("D", "001100");
    try map.put("A", "110000");
    try map.put("!D", "001101");
    try map.put("!A", "110001");
    try map.put("-D", "001111");
    try map.put("-A", "110011");
    try map.put("D+1", "011111");
    try map.put("A+1", "110111");
    try map.put("D-1", "001110");
    try map.put("A-1", "110010");
    try map.put("D+A", "000010");
    try map.put("D-A", "010011");
    try map.put("A-D", "000111");
    try map.put("D&A", "000000");
    try map.put("D|A", "010101");
    try map.put("M", "110000");
    try map.put("!M", "110001");
    try map.put("-M", "110011");
    try map.put("M+1", "110111");
    try map.put("M-1", "110010");
    try map.put("D+M", "000010");
    try map.put("D-M", "010011");
    try map.put("M-D", "000111");
    try map.put("D&M", "000000");
    try map.put("D|M", "010101");

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
        std.log.err("{any} Unrecognized comp: {s}", .{ Self, key });
        std.process.exit(1);
    };
}

test "smoke" {
    var map = try init(std.testing.allocator);
    defer map.deinit();
}
