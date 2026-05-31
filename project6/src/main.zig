const std = @import("std");

const code = @import("code.zig");

pub fn main(init: std.process.Init) !void {
    _ = init;
    if (std.fmt.parseInt(u16, "x42", 10)) |n| {
        std.debug.print("Hello Zig!\n@{b:0>16}\n", .{n});
    } else |_| {
        std.debug.print("Hello Zig!\n@{b:0>16}\n", .{69});
    }
}
