const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const testing = std.testing;

const Self = @This();

allocator: Allocator,
fixedMap: StringHashMap(usize),
allocMap: StringHashMap(usize),

pub fn init(allocator: Allocator) !Self {
    var fixedMap = StringHashMap(usize).init(allocator);
    errdefer fixedMap.deinit();

    try fixedMap.put("SP", 0);
    try fixedMap.put("LCL", 1);
    try fixedMap.put("ARG", 2);
    try fixedMap.put("THIS", 3);
    try fixedMap.put("THAT", 4);
    try fixedMap.put("R0", 0);
    try fixedMap.put("R1", 1);
    try fixedMap.put("R2", 2);
    try fixedMap.put("R3", 3);
    try fixedMap.put("R4", 4);
    try fixedMap.put("R5", 5);
    try fixedMap.put("R6", 6);
    try fixedMap.put("R7", 7);
    try fixedMap.put("R8", 8);
    try fixedMap.put("R9", 9);
    try fixedMap.put("R10", 10);
    try fixedMap.put("R11", 11);
    try fixedMap.put("R12", 12);
    try fixedMap.put("R13", 13);
    try fixedMap.put("R14", 14);
    try fixedMap.put("R15", 15);
    try fixedMap.put("SCREEN", 16384);
    try fixedMap.put("KBD", 24576);

    return .{
        .allocator = allocator,
        .fixedMap = fixedMap,
        .allocMap = .init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    defer self.fixedMap.deinit();
    defer self.allocMap.deinit();

    var it = self.allocMap.iterator();
    while (it.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
    }
}

pub fn get(self: Self, key: []const u8) ?usize {
    if (self.fixedMap.get(key)) |value| {
        return value;
    }

    return self.allocMap.get(key);
}

pub fn put(self: *Self, key: []const u8, value: usize) !void {
    try self.allocMap.put(try self.allocator.dupe(u8, key), value);
}

test "smoke" {
    var map = try init(testing.allocator);
    defer map.deinit();
}

test "put" {
    var map = try init(testing.allocator);
    defer map.deinit();

    try map.put("foo", 1234);
    try testing.expectEqual(map.get("foo").?, 1234);
}
