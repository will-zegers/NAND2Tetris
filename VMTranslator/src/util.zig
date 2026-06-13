const std = @import("std");
const testing = std.testing;

const ParseError = error{
    DuplicateKeys,
    FileTooLarge,
};

pub fn freeMap(map: *std.StringHashMap([]const u8), allocator: std.mem.Allocator) void {
    var entries = map.iterator();
    while (entries.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        allocator.free(entry.value_ptr.*);
    }
    map.deinit();
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
