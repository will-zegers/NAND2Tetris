const std = @import("std");
const process = std.process;
const CodeWriter = @import("./code_writer.zig").CodeWriter;
const Parser = @import("./parser.zig").Parser;

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
        try stdout.writeStreamingAll(init.io, "Usage: VMTranslator <input_file>\n");
        return;
    };
    var it = std.mem.splitScalar(u8, inputPath, '.');
    const baseName = it.first(); // Get the base name so we have a corresponding .asm file as output

    // Output file will have the same base name as the input file but with a .asm extension
    const outputPath = std.fmt.allocPrint(init.gpa, "{s}.asm", .{baseName}) catch unreachable;
    defer init.gpa.free(outputPath);

    //// Run the translator
    // Parser init
    var parser = Parser.init(inputPath, init.io, init.gpa) catch {
        try stdout.writeStreamingAll(init.io, "Error initializing parser\n");
        process.exit(1);
    };
    defer parser.deinit();

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

    // Main translation loop
    while (parser.hasMoreCommands()) {
        parser.advance();
        const commandType = parser.commandType() orelse {
            try stdout.writeStreamingAll(init.io, "Error parsing command: unrecognized command type\n");
            process.exit(1);
        };

        const arg1 = parser.arg1() orelse {
            try stdout.writeStreamingAll(init.io, "Error parsing command: missing location\n");
            process.exit(1);
        };
        switch (commandType) {
            .C_ARITHMETIC => {
                codeWriter.writeArithmetic(arg1.operation) catch {
                    try stdout.writeStreamingAll(init.io, "Error writing arithmetic command\n");
                    process.exit(1);
                };
            },
            .C_GOTO => {
                codeWriter.writeGoto(arg1.label) catch {
                    try stdout.writeStreamingAll(init.io, "Error writing goto command\n");
                    process.exit(1);
                };
            },
            .C_IF => {
                codeWriter.writeIf(arg1.label) catch {
                    try stdout.writeStreamingAll(init.io, "Error writing if-goto command\n");
                    process.exit(1);
                };
            },
            .C_LABEL => {
                codeWriter.writeLabel(arg1.label) catch {
                    try stdout.writeStreamingAll(init.io, "Error creating label\n");
                    process.exit(1);
                };
            },
            .C_PUSH, .C_POP => {
                const index = parser.arg2() orelse {
                    try stdout.writeStreamingAll(init.io, "Error parsing command: missing index\n");
                    process.exit(1);
                };
                codeWriter.writePushPop(commandType, arg1.segment, index) catch {
                    try stdout.writeStreamingAll(init.io, "Error writing push/pop command\n");
                    process.exit(1);
                };
            },
            else => {
                try stdout.writeStreamingAll(init.io, "Unsupported command type\n");
                process.exit(1);
            },
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
