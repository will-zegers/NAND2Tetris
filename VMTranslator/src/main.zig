const std = @import("std");
const ArrayList = std.ArrayList;
const fmt = std.fmt;
const mem = std.mem;
const process = std.process;
const CodeWriter = @import("./code_writer.zig").CodeWriter;
const Parser = @import("./parser.zig").Parser;

pub fn main(init: std.process.Init) !void {
    const stdout = std.Io.File.stdout();

    // Parse input args for the input file or directory
    var iterator =
        try init.minimal.args.iterateAllocator(
            init.gpa,
        );
    defer iterator.deinit();

    _ = iterator.skip(); // skip the executable name
    const inputPath = iterator.next() orelse {
        try stdout.writeStreamingAll(init.io, "Usage: VMTranslator <input_file>\n");
        return;
    };

    // basename will be taken from the input file or directory to name the resulting output .asm file
    var baseName: []const u8 = undefined;
    var inputFilesList: ArrayList([]const u8) = .empty;
    defer {
        inputFilesList.deinit(init.gpa);
    }

    // Check if we were given a directory, in which case we'll parse ALL files within the directory...
    if (std.Io.Dir.cwd().openDir(init.io, inputPath, .{ .iterate = true })) |dir| {
        defer dir.close(init.io);

        var it = dir.iterate();
        while (try it.next(init.io)) |entry| {
            if (mem.endsWith(u8, entry.name, ".vm")) {
                const filePath = try fmt.allocPrint(init.gpa, "{s}/{s}", .{ inputPath, entry.name });
                try inputFilesList.append(init.gpa, filePath);
            }
        }
        var splitter = std.mem.splitScalar(u8, inputPath, '/');
        baseName = splitter.first(); // Set the basename (and output .asm) to the top-level directory name
    } else |err| { // ...or just a single file, in which case we'll parse just that one.
        switch (err) {
            error.NotDir => {
                try inputFilesList.append(init.gpa, inputPath);
                var it = std.mem.splitScalar(u8, inputPath, '.');
                baseName = it.first(); // Output .asm will have the same name as the input .vm
            },
            else => return err,
        }
    }

    const outputPath = std.fmt.allocPrint(init.gpa, "{s}.asm", .{baseName}) catch unreachable;
    defer init.gpa.free(outputPath);

    // CodeWriter init
    var codeWriter = CodeWriter.init(init.io, init.gpa) catch {
        try stdout.writeStreamingAll(init.io, "Error initializing code writer\n");
        process.exit(1);
    };
    defer codeWriter.deinit();
    codeWriter.setFileName(outputPath);
    codeWriter.writeInit() catch {
        try stdout.writeStreamingAll(init.io, "Error writing bootstrap code\n");
        process.exit(1);
    };

    while (inputFilesList.pop()) |filepath| {
        // Parser init
        var parser = Parser.init(filepath, init.io, init.gpa) catch {
            try stdout.writeStreamingAll(init.io, "Error initializing parser\n");
            process.exit(1);
        };
        defer parser.deinit();

        // Main translation loop
        while (parser.hasMoreCommands()) {
            parser.advance();
            const commandType = parser.commandType() orelse {
                try stdout.writeStreamingAll(init.io, "Error parsing command: unrecognized command type\n");
                process.exit(1);
            };

            switch (commandType) {
                .C_ARITHMETIC => {
                    const arg1 = parser.arg1() orelse {
                        try stdout.writeStreamingAll(init.io, "Error parsing command: missing first argument\n");
                        process.exit(1);
                    };
                    codeWriter.writeArithmetic(arg1.operation) catch {
                        try stdout.writeStreamingAll(init.io, "Error writing arithmetic command\n");
                        process.exit(1);
                    };
                },
                .C_CALL => {
                    const arg1 = parser.arg1() orelse {
                        try stdout.writeStreamingAll(init.io, "Error parsing command: missing first argument\n");
                        process.exit(1);
                    };
                    const numArgs = parser.arg2() orelse {
                        try stdout.writeStreamingAll(init.io, "Error parsing command: missing index\n");
                        process.exit(1);
                    };
                    codeWriter.writeCall(arg1.label, numArgs) catch {
                        try stdout.writeStreamingAll(init.io, "Error writing push/pop command\n");
                        process.exit(1);
                    };
                },
                .C_FUNCTION => {
                    const arg1 = parser.arg1() orelse {
                        try stdout.writeStreamingAll(init.io, "Error parsing command: missing first argument\n");
                        process.exit(1);
                    };
                    const numLocals = parser.arg2() orelse {
                        try stdout.writeStreamingAll(init.io, "Error parsing command: missing index\n");
                        process.exit(1);
                    };
                    codeWriter.writeFunction(arg1.label, numLocals) catch {
                        try stdout.writeStreamingAll(init.io, "Error writing push/pop command\n");
                        process.exit(1);
                    };
                },
                .C_GOTO => {
                    const arg1 = parser.arg1() orelse {
                        try stdout.writeStreamingAll(init.io, "Error parsing command: missing first argument\n");
                        process.exit(1);
                    };
                    codeWriter.writeGoto(arg1.label) catch {
                        try stdout.writeStreamingAll(init.io, "Error writing goto command\n");
                        process.exit(1);
                    };
                },
                .C_IF => {
                    const arg1 = parser.arg1() orelse {
                        try stdout.writeStreamingAll(init.io, "Error parsing command: missing first argument\n");
                        process.exit(1);
                    };
                    codeWriter.writeIf(arg1.label) catch {
                        try stdout.writeStreamingAll(init.io, "Error writing if-goto command\n");
                        process.exit(1);
                    };
                },
                .C_LABEL => {
                    const arg1 = parser.arg1() orelse {
                        try stdout.writeStreamingAll(init.io, "Error parsing command: missing first argument\n");
                        process.exit(1);
                    };
                    codeWriter.writeLabel(arg1.label) catch {
                        try stdout.writeStreamingAll(init.io, "Error creating label\n");
                        process.exit(1);
                    };
                },
                .C_PUSH, .C_POP => {
                    const arg1 = parser.arg1() orelse {
                        try stdout.writeStreamingAll(init.io, "Error parsing command: missing first argument\n");
                        process.exit(1);
                    };
                    const index = parser.arg2() orelse {
                        try stdout.writeStreamingAll(init.io, "Error parsing command: missing index\n");
                        process.exit(1);
                    };
                    codeWriter.writePushPop(commandType, arg1.segment, index) catch {
                        try stdout.writeStreamingAll(init.io, "Error writing push/pop command\n");
                        process.exit(1);
                    };
                },
                .C_RETURN => {
                    codeWriter.writeReturn() catch {
                        try stdout.writeStreamingAll(init.io, "Error writing return command\n");
                        process.exit(1);
                    };
                },
            }
        }
    }

    codeWriter.close(init.io) catch {
        try stdout.writeStreamingAll(init.io, "Error closing code writer\n");
        return;
    };

    try stdout.writeStreamingAll(init.io, "File written to ");
    try stdout.writeStreamingAll(init.io, outputPath);
    try stdout.writeStreamingAll(init.io, "\n");
}
