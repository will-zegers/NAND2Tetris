const std = @import("std");
const mem = std.mem;
const process = std.process;
const testing = std.testing;
const StringHashMap = std.StringHashMap;

pub const DestTable = struct {
    const Self = @This();

    allocator: mem.Allocator,
    map: StringHashMap([]const u8),

    pub fn init(allocator: mem.Allocator) !Self {
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
            process.fatal("{any}: Unrecognized dest: '{s}'\n", .{ Self, key });
        };
    }
};

test "smoke" {
    var map = try DestTable.init(testing.allocator);
    defer map.deinit();
}
