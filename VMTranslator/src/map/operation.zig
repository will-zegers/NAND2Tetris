const std = @import("std");
const mem = std.mem;
const StringHashMap = std.StringHashMap;

pub const OperationType = enum {
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

pub const OperationTypeMap = struct {
    const Self = @This();

    map: StringHashMap(OperationType),

    pub fn init(allocator: mem.Allocator) !Self {
        var map = StringHashMap(OperationType).init(allocator);
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

        return Self{ .map = map };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
    }

    pub fn get(self: Self, key: []const u8) ?OperationType {
        return self.map.get(key);
    }
};
