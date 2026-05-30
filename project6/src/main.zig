const std = @import("std");
const Table = @import("table.zig").ParserTable;
const Parser = @import("parser.zig").Parser;
const Code = @import("code.zig").Code;

pub fn main(init: std.process.Init) !void {
    var table = try Table().init("test.table", init.io, init.gpa);
    defer table.deinit();
}
