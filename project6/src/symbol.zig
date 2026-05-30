const std = @import("std");
const testing = std.testing;

const util = @import("util.zig");

const SYMB_FILE = "./table/symbol.table";

pub fn SymbolTable() type {
    return struct {
        const Self = @This();

        table: std.StringHashMap([]const u8),
        allocator: std.mem.Allocator,

        pub fn init(io: std.Io, allocator: std.mem.Allocator) !Self {
            return Self{
                .table = try util.hashmap_from_file(SYMB_FILE, ':', io, allocator),
                .allocator = allocator,
            };
        }

        pub fn contains(self: Self, symbol: []const u8) bool {
            return self.table.contains(symbol);
        }

        pub fn addEntry(self: *Self, symbol: []const u8, address: []const u8) !void {
            try self.table.put(try self.allocator.dupe(u8, symbol), try self.allocator.dupe(u8, address));
        }
        pub fn getAddress(self: Self, symbol: []const u8) ?[]const u8 {
            return self.table.get(symbol);
        }

        pub fn deinit(self: *Self) void {
            util.freeMap(&self.table, self.allocator);
        }
    };
}

test "init" {
    var table = try SymbolTable().init(testing.io, testing.allocator);
    defer table.deinit();

    try testing.expectEqualStrings(table.getAddress("SP").?, "0");
    try testing.expectEqualStrings(table.getAddress("R0").?, "0");
    try testing.expectEqualStrings(table.getAddress("R15").?, "15");
    try testing.expectEqualStrings(table.getAddress("SCREEN").?, "16384");
    try testing.expectEqualStrings(table.getAddress("KBD").?, "24576");
}

test "contains" {
    var table = try SymbolTable().init(testing.io, testing.allocator);
    defer table.deinit();

    try testing.expect(table.contains("SCREEN"));
    try testing.expect(!table.contains("absent"));
}

test "addEntry and getAddress" {
    var table = try SymbolTable().init(testing.io, testing.allocator);
    defer table.deinit();

    try table.addEntry("foo", "12345");
    try testing.expect(table.contains("foo"));
    try testing.expectEqualStrings(table.getAddress("foo").?, "12345");
}
