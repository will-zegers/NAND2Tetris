const std = @import("std");
const Init = std.process.Init;
const Io = std.Io;
const fmt = std.fmt;
const mem = std.mem;

const Assembler = @import("assembler.zig").Assembler;

pub fn main(init: Init) !void {
    const stdout = Io.File.stdout();

    // Parse input args for the .asm file name
    var iterator =
        try init.minimal.args.iterateAllocator(
            init.gpa,
        );
    defer iterator.deinit();

    _ = iterator.skip(); // skip the executable name
    const inputPath = iterator.next() orelse {
        try stdout.writeStreamingAll(init.io, "Usage: hack-assembler <input_file>\n");
        return;
    };
    var it = mem.tokenizeScalar(u8, inputPath, '.');
    var baseName: []const u8 = undefined;
    var previous: []const u8 = undefined;
    while (it.peek()) |_| {
        baseName = previous;
        previous = it.next().?;
    }

    // Run the assembler
    var assembler = try Assembler.init(inputPath, init.io, init.gpa);
    defer assembler.deinit();

    const output = try assembler.assemble(init.gpa);
    defer init.gpa.free(output);

    // Write out to a .hack file
    const outputPath = try fmt.allocPrint(init.gpa, "{s}.hack", .{baseName});
    defer init.gpa.free(outputPath);

    const outputFile = try Io.Dir.cwd().createFile(init.io, outputPath, .{ .read = false });
    defer outputFile.close(init.io);

    try outputFile.writePositionalAll(init.io, output, 0);

    try stdout.writeStreamingAll(init.io, "File written to ");
    try stdout.writeStreamingAll(init.io, outputPath);
    try stdout.writeStreamingAll(init.io, "\n");
}
