const std = @import("std");
const testing = std.testing;

const BUFFER_SIZE = 1024 * 1024;

const ParseError = error{
    DuplicateKeys,
    FileTooLarge,
};

pub fn hashmap_from_file(filename: []const u8, delimiter: u8, io: std.Io, allocator: std.mem.Allocator) !std.StringHashMap([]const u8) {
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

pub fn freeMap(map: *std.StringHashMap([]const u8), allocator: std.mem.Allocator) void {
    var entries = map.iterator();
    while (entries.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        allocator.free(entry.value_ptr.*);
    }
    map.deinit();
}

pub fn readASMFile(asm_file: []const u8, buffer: []u8, io: std.Io) !usize {
    const input_file = try std.Io.Dir.cwd().openFile(io, asm_file, .{ .mode = .read_only });
    var fr = input_file.reader(io, buffer);
    var reader = &fr.interface;

    var total_bytes: usize = 0;
    while (true) {
        const bytes_read = reader.readSliceShort(buffer[total_bytes..]) catch 0;
        if (total_bytes + bytes_read >= BUFFER_SIZE) {
            std.process.fatal("Input file is too large. Max size is {d} bytes.\n", .{BUFFER_SIZE});
        }
        if (bytes_read == 0) {
            break;
        }
        total_bytes += bytes_read;
    }
    return total_bytes;
}

pub fn contains(haystack: []const u8, needle: u8) bool {
    for (haystack) |char| {
        if (char == needle) {
            return true;
        }
    }
    return false;
}

test "hashmap_from_file no duplicates" {
    var map = try hashmap_from_file("./test/test.table", ':', testing.io, testing.allocator);
    defer freeMap(&map, testing.allocator);

    try testing.expectEqualStrings(map.get("fern").?, "willow");
}

test "hashmap_from_file fail on duplicates" {
    const err = hashmap_from_file("./test/test_dupes.table", ':', testing.io, testing.allocator);
    try testing.expect(err == ParseError.DuplicateKeys);
}

test "freeMap" {
    var map = try hashmap_from_file("./test/test.table", ':', testing.io, testing.allocator);
    defer freeMap(&map, testing.allocator);
}

test "readASMFile" {
    const file_path = "./test/Test.asm";
    var buffer: [BUFFER_SIZE]u8 = undefined;
    const length = try readASMFile(file_path, &buffer, testing.io);
    try testing.expect(length == 730);
}
