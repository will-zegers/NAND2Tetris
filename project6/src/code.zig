const std = @import("std");
const testing = std.testing;

const COMP_FILE = "comp.table";
const DEST_FILE = "dest.table";
const JUMP_FILE = "jump.table";

const BUFFER_SIZE = 1024;

const ParseError = error{
    DuplicateKeys,
    FileTooLarge,
};

pub fn Code() type {
    return struct {
        const Self = @This();

        comp_table: std.StringHashMap([]const u8),
        dest_table: std.StringHashMap([]const u8),
        jump_table: std.StringHashMap([]const u8),
        allocator: std.mem.Allocator,

        pub fn init(io: std.Io, allocator: std.mem.Allocator) !Self {
            return Self{
                .comp_table = try hashmap_from_file(COMP_FILE, ':', io, allocator),
                .dest_table = try hashmap_from_file(DEST_FILE, ':', io, allocator),
                .jump_table = try hashmap_from_file(JUMP_FILE, ':', io, allocator),
                .allocator = allocator,
            };
        }

        pub fn dest(self: Self, mnemonic: []const u8) ?[]const u8 {
            return self.dest_table.get(mnemonic);
        }

        pub fn comp(self: Self, mnemonic: []const u8) ?[]const u8 {
            return self.comp_table.get(mnemonic);
        }

        pub fn jump(self: Self, mnemonic: []const u8) ?[]const u8 {
            return self.jump_table.get(mnemonic);
        }

        pub fn deinit(self: *Self) void {
            freeMap(&self.comp_table, self.allocator);
            freeMap(&self.dest_table, self.allocator);
            freeMap(&self.jump_table, self.allocator);
        }
    };
}

fn hashmap_from_file(filename: []const u8, delimiter: u8, io: std.Io, allocator: std.mem.Allocator) !std.StringHashMap([]const u8) {
    const file = try std.Io.Dir.cwd().openFile(io, filename, .{ .mode = .read_only });
    defer file.close(io);

    var buffer: [BUFFER_SIZE]u8 = undefined;

    var fr = file.reader(io, &buffer);
    var reader = &fr.interface;
    var total_bytes: usize = 0;
    while (true) {
        const bytes_read = reader.readSliceShort(buffer[total_bytes..]) catch 0;
        if (total_bytes + bytes_read >= BUFFER_SIZE) {
            return ParseError.FileTooLarge;
        }
        if (bytes_read == 0) {
            break;
        }
        total_bytes += bytes_read;
    }
    var lines = std.mem.splitScalar(u8, buffer[0 .. total_bytes - 1], '\n');

    var map = std.StringHashMap([]const u8).init(allocator);

    while (lines.next()) |line| {
        var key_val = std.mem.splitScalar(u8, line, delimiter);
        const key = key_val.next() orelse unreachable;
        const value = key_val.next() orelse unreachable;

        if (map.contains(key)) { // tables should not have duplicate keys and result in clobbering
            freeMap(&map, allocator);
            return ParseError.DuplicateKeys;
        } else {
            try map.put(try allocator.dupe(u8, key), try allocator.dupe(u8, value));
        }
    }

    return map;
}

fn freeMap(map: *std.StringHashMap([]const u8), allocator: std.mem.Allocator) void {
    var entries = map.iterator();
    while (entries.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        allocator.free(entry.value_ptr.*);
    }
    map.deinit();
}

test "init" {
    var code = try Code().init(testing.io, testing.allocator);
    defer code.deinit();
}

test "comp" {
    var code = try Code().init(testing.io, testing.allocator);
    defer code.deinit();

    const comp = code.comp("D|M").?;
    try testing.expectEqualStrings(comp, "010101");
}

test "dest" {
    var code = try Code().init(testing.io, testing.allocator);
    defer code.deinit();

    const dest = code.dest("MD").?;
    try testing.expectEqualStrings(dest, "011");
}

test "jump" {
    var code = try Code().init(testing.io, testing.allocator);
    defer code.deinit();

    const jump = code.jump("JGT").?;
    try testing.expectEqualStrings(jump, "001");
}
