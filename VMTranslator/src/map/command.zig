const std = @import("std");
const mem = std.mem;
const StringHashMap = std.StringHashMap;

pub const CommandType = enum {
    C_ARITHMETIC,
    C_CALL,
    C_FUNCTION,
    C_GOTO,
    C_IF,
    C_LABEL,
    C_POP,
    C_PUSH,
    C_RETURN,
};

pub const CommandTypeMap = struct {
    const Self = @This();

    allocator: mem.Allocator,
    map: std.StringHashMap(CommandType),

    pub fn init(allocator: mem.Allocator) !Self {
        var map = std.StringHashMap(CommandType).init(allocator);
        errdefer map.deinit();

        try map.put("add", .C_ARITHMETIC);
        try map.put("sub", .C_ARITHMETIC);
        try map.put("neg", .C_ARITHMETIC);
        try map.put("eq", .C_ARITHMETIC);
        try map.put("gt", .C_ARITHMETIC);
        try map.put("lt", .C_ARITHMETIC);
        try map.put("and", .C_ARITHMETIC);
        try map.put("or", .C_ARITHMETIC);
        try map.put("not", .C_ARITHMETIC);
        try map.put("call", .C_CALL);
        try map.put("function", .C_FUNCTION);
        try map.put("goto", .C_GOTO);
        try map.put("if", .C_IF);
        try map.put("label", .C_LABEL);
        try map.put("pop", .C_POP);
        try map.put("push", .C_PUSH);
        try map.put("return", .C_RETURN);

        return Self{ .allocator = allocator, .map = map };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
    }

    pub fn get(self: Self, key: []const u8) ?CommandType {
        return self.map.get(key);
    }
};
