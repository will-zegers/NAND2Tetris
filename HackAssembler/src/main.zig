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
    const inputPath = iterator.next() orelse {
        try stdout.writeStreamingAll(init.io, "Usage: hack-assembler <input_file>.asm\n");
        return;
    };
    var it = std.mem.splitScalar(u8, inputPath, '.');
    var baseName: []const u8 = undefined;
    var previous: []const u8 = undefined;
    while (it.peek()) |_| {
        baseName = previous;
        previous = it.next().?;
    }

    // Run the assembler
    var assembler = try Assembler.init(inputPath, init.io, init.gpa);
    defer assembler.deinit();
    const output = try assembler.assemble();

    // Write out to a .hack file
    const outputPath = std.fmt.allocPrint(init.gpa, "{s}.hack", .{baseName}) catch unreachable;
    defer init.gpa.free(outputPath);

    const cwd = std.Io.Dir.cwd();
    const outputFile = try cwd.createFile(init.io, outputPath, .{ .read = false });
    defer outputFile.close(init.io);
    _ = try outputFile.writePositionalAll(init.io, output, 0);

    try stdout.writeStreamingAll(init.io, "File written to ");
    try stdout.writeStreamingAll(init.io, outputPath);
    try stdout.writeStreamingAll(init.io, "\n");
}
