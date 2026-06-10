const std = @import("std");
const CodeWriter = @import("./code_writer.zig").CodeWriter;

const CommandType = enum {
    C_ARITHMETIC,
    C_CALL,
    C_FUNCTION,
    C_GOTO,
    C_IF,
    C_LABEL,
    C_POP,
    C_PUSH,
    C_RETURN,
};

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
        try stdout.writeStreamingAll(init.io, "Usage: VMTranslator <input_file>.vm\n");
        return;
    };
    var it = std.mem.splitScalar(u8, inputPath, '.');
    const baseName = it.first(); // Get the base name so we have a corresponding .asm file as output

    // Run the assembler
    var code_writer = try CodeWriter.init(inputPath, init.io, init.gpa);
    defer code_writer.deinit();
    const output = try code_writer.run();

    // Write out to a .hack file
    const outputPath = std.fmt.allocPrint(init.gpa, "{s}.asm", .{baseName}) catch unreachable;
    defer init.gpa.free(outputPath);

    const cwd = std.Io.Dir.cwd();
    const outputFile = try cwd.createFile(init.io, outputPath, .{ .read = false });
    defer outputFile.close(init.io);
    _ = try outputFile.writePositionalAll(init.io, output, 0);

    try stdout.writeStreamingAll(init.io, "File written to ");
    try stdout.writeStreamingAll(init.io, outputPath);
    try stdout.writeStreamingAll(init.io, "\n");
}
