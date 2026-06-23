const std = @import("std");
const ArrayList = std.ArrayList;
const Init = std.process.Init;
const Io = std.Io;
const fmt = std.fmt;
const mem = std.mem;
const process = std.process;

const Translator = @import("Translator.zig");

pub fn main(init: Init) !void {
    // Parse input args for the input file or directory
    var args =
        try init.minimal.args.iterateAllocator(
            init.gpa,
        );
    defer args.deinit();

    _ = args.skip(); // skip the executable name
    const inputPath = args.next() orelse {
        try Io.File.stdout().writeStreamingAll(init.io, "Usage: VMTranslator <input_file>\n");
        return;
    };

    // basename will be taken from the input file or directory to name the resulting output .asm file
    var baseName: []const u8 = undefined;
    var inputFilesList: ArrayList([]const u8) = .empty;
    defer {
        for (inputFilesList.items) |item| {
            init.gpa.free(item);
        }
        inputFilesList.deinit(init.gpa);
    }

    // Check if we were given a directory, in which case we'll parse ALL files within the directory...
    if (Io.Dir.cwd().openDir(init.io, inputPath, .{ .iterate = true })) |dir| {
        defer dir.close(init.io);

        var it = dir.iterate();
        while (try it.next(init.io)) |entry| {
            if (mem.endsWith(u8, entry.name, ".vm")) {
                const filePath = try fmt.allocPrint(init.gpa, "{s}/{s}", .{ inputPath, entry.name });
                try inputFilesList.append(init.gpa, filePath);
            }
        }
        baseName = if (mem.endsWith(u8, inputPath, "/")) inputPath[0 .. inputPath.len - 1] else inputPath;
    } else |err| { // ...or just a single file, in which case we'll parse just that one.
        switch (err) {
            error.NotDir => {
                try inputFilesList.append(init.gpa, try init.gpa.dupe(u8, inputPath));
                var it = mem.splitScalar(u8, inputPath, '.');
                baseName = it.first(); // Output .asm will have the same name as the input .vm
            },
            else => return err,
        }
    }

    const outputPath = fmt.allocPrint(init.gpa, "{s}.asm", .{baseName}) catch unreachable;
    defer init.gpa.free(outputPath);

    var translator = try Translator.init(init.gpa, init.io, outputPath);
    defer translator.deinit();

    while (inputFilesList.pop()) |filepath| {
        defer init.gpa.free(filepath);
        try translator.translate(filepath);
    }
    try translator.close();

    std.log.info("File written to {s}", .{outputPath});
}
