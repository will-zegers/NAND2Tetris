const std = @import("std");
const mem = std.mem;
const AutoHashMap = std.AutoHashMap;

const mSegment = @import("segment.zig");
const SegmentType = mSegment.SegmentType;

pub const BaseAddressMap = struct {
    const Self = @This();

    map: AutoHashMap(SegmentType, u16),

    pub fn init(allocator: mem.Allocator) !Self {
        var map = AutoHashMap(SegmentType, u16).init(allocator);
        errdefer map.deinit();

        try map.put(.Constant, 0);
        try map.put(.Pointer, 3);
        try map.put(.Temp, 5);
        try map.put(.Static, 16);

        return Self{ .map = map };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
    }

    pub fn get(self: Self, key: SegmentType) ?u16 {
        return self.map.get(key);
    }
};
