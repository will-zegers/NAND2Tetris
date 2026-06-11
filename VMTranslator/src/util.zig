const std = @import("std");
const testing = std.testing;

const BUFFER_SIZE = 1024 * 1024;

const ParseError = error{
    DuplicateKeys,
    FileTooLarge,
};

pub fn hashmapFromFile(filename: []const u8, delimiter: u8, io: std.Io, allocator: std.mem.Allocator) !std.StringHashMap([]const u8) {
    const content = try std.Io.Dir.cwd().readFileAlloc(io, filename, allocator, .unlimited);
    defer allocator.free(content);

    var map = std.StringHashMap([]const u8).init(allocator);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        var keyValue = std.mem.splitScalar(u8, line, delimiter);
        const key = keyValue.next() orelse continue; // ignore lines with no content
        const value = keyValue.next() orelse continue;

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
            return ParseError.FileTooLarge;
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

test "hashmapFromFile" {
    var map = try hashmapFromFile("./test/test.table", ':', testing.io, testing.allocator);
    defer freeMap(&map, testing.allocator);

    try testing.expectEqualStrings(map.get("fern").?, "willow");
}

test "hashmapFromFile fail on duplicate keys" {
    const err = hashmapFromFile("./test/test_dupes.table", ':', testing.io, testing.allocator);
    try testing.expectEqual(err, ParseError.DuplicateKeys);
}

test "freeMap" {
    var map = try hashmapFromFile("./test/test.table", ':', testing.io, testing.allocator);
    defer freeMap(&map, testing.allocator);
}

test "readFile" {
    const filePath = "./test/BasicTest.vm";
    var buffer: [BUFFER_SIZE]u8 = undefined;
    const length = try readFile(filePath, &buffer, testing.io);
    try testing.expectEqual(length, 535);
}
