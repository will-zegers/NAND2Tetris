const std = @import("std");
const mem = std.mem;
const StringHashMap = std.StringHashMap;

pub const SegmentType = enum {
    Local,
    Argument,
    Pointer,
    This,
    That,
    Temp,
    Static,
    Constant,
};

pub const SegmentTypeMap = struct {
    const Self = @This();

    map: StringHashMap(SegmentType),

    pub fn init(allocator: mem.Allocator) !Self {
        var map = StringHashMap(SegmentType).init(allocator);
        errdefer map.deinit();

        try map.put("local", .Local);
        try map.put("argument", .Argument);
        try map.put("pointer", .Pointer);
        try map.put("this", .This);
        try map.put("that", .That);
        try map.put("temp", .Temp);
        try map.put("static", .Static);
        try map.put("constant", .Constant);

        return Self{ .map = map };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
    }

    pub fn get(self: Self, key: []const u8) ?SegmentType {
        return self.map.get(key);
    }
};
