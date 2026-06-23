const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const testing = std.testing;

const Segment = @import("SegmentMap.zig").Type;

const Self = @This();

map: AutoHashMap(Segment, u16),

pub fn init(allocator: Allocator) !Self {
    var map = AutoHashMap(Segment, u16).init(allocator);
    errdefer map.deinit();

    try map.put(.Constant, 0);
    try map.put(.Pointer, 3);
    try map.put(.Temp, 5);
    try map.put(.Static, 16);

    return .{ .map = map };
}

pub fn deinit(self: *Self) void {
    self.map.deinit();
}

pub fn get(self: Self, key: Segment) usize {
    return self.map.get(key) orelse {
        std.log.err("'{}' is not a valid segment with a base address", .{key});
        std.process.exit(1);
    };
}

test "smoke" {
    var map = try init(testing.allocator);
    defer map.deinit();
}
