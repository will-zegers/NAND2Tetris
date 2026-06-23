const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const testing = std.testing;

const Self = @This();

pub const Type = enum {
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

allocator: Allocator,
map: StringHashMap(Type),

pub fn init(allocator: Allocator) !Self {
    var map = StringHashMap(Type).init(allocator);
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
    try map.put("if-goto", .C_IF);
    try map.put("label", .C_LABEL);
    try map.put("pop", .C_POP);
    try map.put("push", .C_PUSH);
    try map.put("return", .C_RETURN);

    return .{ .allocator = allocator, .map = map };
}

pub fn deinit(self: *Self) void {
    self.map.deinit();
}

pub fn get(self: Self, key: []const u8) Type {
    return self.map.get(key) orelse {
        std.log.err("'{s}' is not a valid command", .{key});
        std.process.exit(1);
    };
}

test "smoke" {
    var map = try init(testing.allocator);
    defer map.deinit();
}
