const std = @import("std");
const CodeWriter = @import("./code_writer.zig").CodeWriter;
const Parser = @import("./parser.zig").Parser;

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
        try stdout.writeStreamingAll(init.io, "Usage: VMTranslator <input_file>\n");
        return;
    };
    var it = std.mem.splitScalar(u8, inputPath, '.');
    const baseName = it.first(); // Get the base name so we have a corresponding .asm file as output

    // Write out to a .hack file
    const outputPath = std.fmt.allocPrint(init.gpa, "{s}.asm", .{baseName}) catch unreachable;
    defer init.gpa.free(outputPath);

    // Run the translator
    var parser = Parser.init(inputPath, init.io, init.gpa) catch {
        try stdout.writeStreamingAll(init.io, "Error initializing parser\n");
        return;
    };
    defer parser.deinit();

    var codeWriter = CodeWriter.init(init.io, init.gpa) catch {
        try stdout.writeStreamingAll(init.io, "Error initializing code writer\n");
        return;
    };
    defer codeWriter.deinit();
    codeWriter.setFileName(outputPath);

    while (parser.hasMoreCommands()) {
        parser.advance();
        const commandType = parser.commandType() orelse {
            try stdout.writeStreamingAll(init.io, "Error parsing command: unrecognized command type\n");
            return;
        };
        if (commandType == .C_PUSH or commandType == .C_POP) {
            const location = parser.arg1() orelse {
                try stdout.writeStreamingAll(init.io, "Error parsing command: missing location\n");
                return;
            };
            const index = parser.arg2() orelse {
                try stdout.writeStreamingAll(init.io, "Error parsing command: missing index\n");
                return;
            };
            codeWriter.writePushPop(commandType, location, index) catch {
                try stdout.writeStreamingAll(init.io, "Error writing push/pop command\n");
                return;
            };
        } else if (commandType == .C_ARITHMETIC) {
            const operation = parser.arg0() orelse {
                try stdout.writeStreamingAll(init.io, "Error parsing command: missing operation\n");
                return;
            };
            codeWriter.writeArithmetic(operation) catch {
                try stdout.writeStreamingAll(init.io, "Error writing arithmetic command\n");
                return;
            };
        } else {
            try stdout.writeStreamingAll(init.io, "Unsupported command type\n");
            return;
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
