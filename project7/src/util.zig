const std = @import("std");
const testing = std.testing;

const BUFFER_SIZE = 1024 * 1024;

const ParseError = error{
    DuplicateKeys,
    FileTooLarge,
};

pub fn hashmapFromFile(filename: []const u8, delimiter: u8, io: std.Io, allocator: std.mem.Allocator) !std.StringHashMap([]const u8) {
    const file = try std.Io.Dir.cwd().openFile(io, filename, .{ .mode = .read_only });
    defer file.close(io);

    var buffer: [BUFFER_SIZE]u8 = undefined;

    var fr = file.reader(io, &buffer);
    var reader = &fr.interface;
    var totalBytes: usize = 0;
    while (true) {
        const bytesRead = reader.readSliceShort(buffer[totalBytes..]) catch 0;
        if (totalBytes + bytesRead >= BUFFER_SIZE) {
            return ParseError.FileTooLarge;
        }
        if (bytesRead == 0) {
            break;
        }
        totalBytes += bytesRead;
    }
    var lines = std.mem.splitScalar(u8, buffer[0 .. totalBytes - 1], '\n');

    var map = std.StringHashMap([]const u8).init(allocator);

    while (lines.next()) |line| {
        var keyValue = std.mem.splitScalar(u8, line, delimiter);
        const key = keyValue.next() orelse unreachable;
        const value = keyValue.next() orelse unreachable;

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

pub fn readFile(asmFile: []const u8, buffer: []u8, io: std.Io) !usize {
    const inputFile = try std.Io.Dir.cwd().openFile(io, asmFile, .{ .mode = .read_only });
    var fr = inputFile.reader(io, buffer);
    var reader = &fr.interface;

    var totalBytes: usize = 0;
    while (true) {
        const bytesRead = reader.readSliceShort(buffer[totalBytes..]) catch 0;
        if (totalBytes + bytesRead >= BUFFER_SIZE) {
            std.process.fatal("Input file is too large. Max size is {d} bytes.\n", .{BUFFER_SIZE});
        }
        if (bytesRead == 0) {
            break;
        }
        totalBytes += bytesRead;
    }
    return totalBytes;
}

pub fn contains(haystack: []const u8, needle: u8) bool {
    for (haystack) |char| {
        if (char == needle) {
            return true;
        }
    }
    return false;
}

pub fn trim(string: []const u8) []const u8 {
    var startIndex: usize = 0;
    for (string) |c| {
        if (!isWhiteSpace(c)) {
            break;
        }
        startIndex += 1;
    }

    var endIndex: usize = string.len;
    for (0..string.len) |i| {
        if (!isWhiteSpace(string[string.len - i - 1])) {
            break;
        }
        endIndex -= 1;
    }

    return string[startIndex..endIndex];
}

pub fn isWhiteSpace(char: u8) bool {
    return (char == '\t' or char == ' ');
}

// test "hashmapFromFile no duplicates" {
//     var map = try hashmapFromFile("./test/test.table", ':', testing.io, testing.allocator);
//     defer freeMap(&map, testing.allocator);
//
//     try testing.expectEqualStrings(map.get("fern").?, "willow");
// }
//
// test "hashmapFromFile fail on duplicates" {
//     const err = hashmapFromFile("./test/test_dupes.table", ':', testing.io, testing.allocator);
//     try testing.expect(err == ParseError.DuplicateKeys);
// }
//
// test "freeMap" {
//     var map = try hashmapFromFile("./test/test.table", ':', testing.io, testing.allocator);
//     defer freeMap(&map, testing.allocator);
// }
//
// test "readASMFile" {
//     const filePath = "./test/Test.asm";
//     var buffer: [BUFFER_SIZE]u8 = undefined;
//     const length = try readASMFile(filePath, &buffer, testing.io);
//     try testing.expect(length == 730);
// }
