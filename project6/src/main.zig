const std = @import("std");

const Assembler = @import("assembler.zig").Assembler;

pub fn main(init: std.process.Init) !void {
    const stdout = std.Io.File.stdout();

    // Parse input args for the .asm file name
    var iterator =
        try init.minimal.args.iterateAllocator(
            init.gpa,
        );
    defer iterator.deinit();

    _ = iterator.skip(); // skip the executable name
    const input_path = iterator.next() orelse {
        try stdout.writeStreamingAll(init.io, "Usage: hack-assembler <input_file>.asm\n");
        return;
    };
    var it = std.mem.splitScalar(u8, input_path, '.');
    const base_name = it.first(); // Get the base name so we have a corresponding .hack file as output

    // Run the assembler
    var assembler = try Assembler.init(input_path, init.io, init.gpa);
    defer assembler.deinit();
    const output = try assembler.assemble();

    // Write out to a .hack file
    const output_path = std.fmt.allocPrint(init.gpa, "{s}.hack", .{base_name}) catch unreachable;
    defer init.gpa.free(output_path);

    const cwd = std.Io.Dir.cwd();
    const output_file = try cwd.createFile(init.io, output_path, .{ .read = false });
    defer output_file.close(init.io);
    _ = try output_file.writePositionalAll(init.io, output, 0);

    try stdout.writeStreamingAll(init.io, "File written to ");
    try stdout.writeStreamingAll(init.io, output_path);
    try stdout.writeStreamingAll(init.io, "\n");
}
