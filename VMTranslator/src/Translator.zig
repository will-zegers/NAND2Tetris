const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Io = std.Io;
const log = std.log;
const process = std.process;
const testing = std.testing;

const CodeWriter = @import("CodeWriter.zig");
const Parser = @import("Parser.zig");

const Self = @This();

allocator: Allocator,
io: Io,
codeWriter: CodeWriter,

pub fn init(allocator: Allocator, io: Io, outputPath: []const u8) !Self {
    var codeWriter = try CodeWriter.init(allocator, io, outputPath);
    try codeWriter.writeInit();

    return .{
        .allocator = allocator,
        .io = io,
        .codeWriter = codeWriter,
    };
}

pub fn deinit(self: *Self) void {
    defer self.codeWriter.deinit();
}

pub fn translate(self: *Self, inputPath: []const u8) !void {
    self.codeWriter.setFileName(inputPath);
    var parser = try Parser.init(self.allocator, self.io, inputPath);
    defer parser.deinit();

    log.info("Translating file {s}", .{inputPath});
    while (parser.hasMoreCommands()) {
        parser.advance();
        const commandType = parser.commandType() orelse {
            log.err("Error parsing command: unrecognized command type", .{});
            process.exit(1);
        };

        switch (commandType) {
            .C_ARITHMETIC => {
                const arg1 = parser.arg1() orelse {
                    log.err("Error parsing command: missing first argument", .{});
                    process.exit(1);
                };
                self.codeWriter.writeArithmetic(arg1.operation) catch |err| {
                    log.err("Error writing arithmetic command: {t}", .{err});
                    process.exit(1);
                };
            },
            .C_CALL => {
                const arg1 = parser.arg1() orelse {
                    log.err("Error parsing command: missing first argument", .{});
                    process.exit(1);
                };
                const numArgs = parser.arg2() orelse {
                    log.err("Error parsing command: missing index", .{});
                    process.exit(1);
                };
                self.codeWriter.writeCall(arg1.label, numArgs) catch |err| {
                    log.err("Error writing push/pop command: {t}", .{err});
                    process.exit(1);
                };
            },
            .C_FUNCTION => {
                const arg1 = parser.arg1() orelse {
                    log.err("Error parsing command: missing first argument", .{});
                    process.exit(1);
                };
                const numLocals = parser.arg2() orelse {
                    log.err("Error parsing command: missing index", .{});
                    process.exit(1);
                };
                self.codeWriter.writeFunction(arg1.label, numLocals) catch |err| {
                    log.err("Error writing push/pop command: {t}", .{err});
                    process.exit(1);
                };
            },
            .C_GOTO => {
                const arg1 = parser.arg1() orelse {
                    log.err("Error parsing command: missing first argument", .{});
                    process.exit(1);
                };
                self.codeWriter.writeGoto(arg1.label) catch |err| {
                    log.err("Error writing goto command: {t}", .{err});
                    process.exit(1);
                };
            },
            .C_IF => {
                const arg1 = parser.arg1() orelse {
                    log.err("Error parsing command: missing first argument", .{});
                    process.exit(1);
                };
                self.codeWriter.writeIf(arg1.label) catch |err| {
                    log.err("Error writing if-goto command: {t}", .{err});
                    process.exit(1);
                };
            },
            .C_LABEL => {
                const arg1 = parser.arg1() orelse {
                    log.err("Error parsing command: missing first argument", .{});
                    process.exit(1);
                };
                self.codeWriter.writeLabel(arg1.label) catch |err| {
                    log.err("Error creating label: {t}", .{err});
                    process.exit(1);
                };
            },
            .C_PUSH, .C_POP => {
                const arg1 = parser.arg1() orelse {
                    log.err("Error parsing command: missing first argument", .{});
                    process.exit(1);
                };
                const index = parser.arg2() orelse {
                    log.err("Error parsing command: missing index", .{});
                    process.exit(1);
                };
                self.codeWriter.writePushPop(commandType, arg1.segment, index) catch |err| {
                    log.err("Error writing push/pop command: {t}", .{err});
                    process.exit(1);
                };
            },
            .C_RETURN => {
                self.codeWriter.writeReturn() catch |err| {
                    log.err("Error writing return command: {t}", .{err});
                    process.exit(1);
                };
            },
        }
    }
}

pub fn close(self: Self) !void {
    try self.codeWriter.close(self.io);
}

test "smoke" {
    var translator = try init(testing.allocator, testing.io, "./test/BasicTest.asm");
    defer translator.deinit();
}

test "translate" {
    var translator = try init(testing.allocator, testing.io, "./test/BasicTest.asm");
    defer translator.deinit();

    try translator.translate("./test/BasicTest.vm");
}
