const std = @import("std");
const testing = std.testing;

const FILE_BUFFER_SIZE = 1024 * 1024;

const CommandType = enum {
    A_COMMAND,
    C_COMMAND,
    L_COMMAND,
};

pub fn Parser() type {
    return struct {
        const Self = @This();

        pc_value: usize,
        bytes_out: usize,
        file_line_num: usize,
        current_instruction: ?[]const u8,
        instructions: std.mem.SplitIterator(u8, .scalar),

        pub fn init(input_path: []const u8, io: std.Io) !Self {
            var in_buf: [FILE_BUFFER_SIZE]u8 = undefined;

            const input_file = try std.Io.Dir.cwd().openFile(io, input_path, .{ .mode = .read_only });
            var fr = input_file.reader(io, &in_buf);
            var reader = &fr.interface;

            var total_bytes: usize = 0;
            while (true) {
                const bytes_read = reader.readSliceShort(in_buf[total_bytes..]) catch 0;
                if (total_bytes + bytes_read >= FILE_BUFFER_SIZE) {
                    std.process.fatal("Input file is too large. Max size is {d} bytes.\n", .{FILE_BUFFER_SIZE});
                }
                if (bytes_read == 0) {
                    break;
                }
                total_bytes += bytes_read;
            }
            const instructions = std.mem.splitScalar(u8, in_buf[0 .. total_bytes - 1], '\n');

            return Self{
                .pc_value = 0,
                .bytes_out = 0,
                .file_line_num = 0,
                .current_instruction = null,
                .instructions = instructions,
            };
        }

        pub fn hasMoreCommands(self: *Self) bool {
            return self.instructions.peek() != null;
        }

        pub fn advance(self: *Self) void {
            while (self.instructions.next()) |next| {
                const instruction = trim(next);
                if (std.mem.startsWith(u8, instruction, "//") or next.len == 0) {
                    continue;
                }
                self.current_instruction = instruction;
                return;
            }
            self.current_instruction = null;
        }

        pub fn commandType(self: *Self) ?CommandType {
            if (self.current_instruction == null) {
                return null;
            } else if (std.mem.startsWith(u8, self.current_instruction.?, "@")) {
                return .A_COMMAND;
            } else if (std.mem.startsWith(u8, self.current_instruction.?, "(") and std.mem.endsWith(u8, self.current_instruction.?, ")")) {
                return .L_COMMAND;
            } else {
                return .C_COMMAND;
            }
        }

        pub fn symbol(self: *Self) ?[]const u8 {
            if (self.commandType() != .L_COMMAND) {
                return null;
            }

            const length = self.current_instruction.?.len;
            return self.current_instruction.?[1 .. length - 1];
        }

        pub fn dest(self: *Self) ?[]const u8 {
            var c_instruction = std.mem.splitScalar(u8, self.current_instruction.?, '=');
            return c_instruction.first();
        }

        pub fn comp(self: *Self) ?[]const u8 {
            if (instructionContains(self.current_instruction.?, ';')) {
                var c_instruction = std.mem.splitScalar(u8, self.current_instruction.?, ';');
                return c_instruction.first();
            }

            var c_instruction = std.mem.splitScalar(u8, self.current_instruction.?, '=');
            _ = c_instruction.next();
            return c_instruction.next();
        }

        pub fn jump(self: *Self) ?[]const u8 {
            var c_instruction = std.mem.splitScalar(u8, self.current_instruction.?, ';');
            _ = c_instruction.next();
            return c_instruction.next();
        }
    };
}

fn instructionContains(haystack: []const u8, needle: u8) bool {
    for (haystack) |char| {
        if (char == needle) {
            return true;
        }
    }
    return false;
}

fn trim(string: []const u8) []const u8 {
    var start_index: usize = 0;
    for (string) |c| {
        if (!isWhiteSpace(c)) {
            break;
        }
        start_index += 1;
    }

    var end_index: usize = string.len;
    for (0..string.len) |i| {
        if (!isWhiteSpace(string[string.len - i - 1])) {
            break;
        }
        end_index -= 1;
    }

    return string[start_index..end_index];
}

fn isWhiteSpace(char: u8) bool {
    return (char == '\t' or char == ' ');
}

test "init" {
    const parser = try Parser().init("./test/Test.asm", testing.io);
    try testing.expect(@TypeOf(parser) == Parser());
}

test "hasMoreCommands" {
    var parser = try Parser().init("./test/Test.asm", testing.io);
    try testing.expect(parser.hasMoreCommands());
    parser.advance();
    try testing.expect(parser.hasMoreCommands());
    for (0..31) |_| {
        parser.advance();
    }
    try testing.expect(!parser.hasMoreCommands());
}

test "advance" {
    var parser = try Parser().init("./test/Test.asm", testing.io);
    try testing.expect(parser.current_instruction == null);
    for (0..27) |_| {
        parser.advance();
    }
    try testing.expect(parser.current_instruction != null);
    parser.advance();
    try testing.expect(parser.current_instruction == null);
}

test "commandType" {
    var parser = try Parser().init("./test/Test.asm", testing.io);
    parser.advance();
    try testing.expect(parser.commandType().? == .A_COMMAND);
    parser.advance();
    try testing.expect(parser.commandType().? == .C_COMMAND);
    for (0..9) |_| {
        parser.advance();
    }
    try testing.expect(parser.commandType().? == .L_COMMAND);
}

test "symbol" {
    var parser = try Parser().init("./test/Test.asm", testing.io);
    parser.advance();
    for (0..9) |_| {
        parser.advance();
        try testing.expect(parser.symbol() == null);
    }
    parser.advance();
    try testing.expect(std.mem.eql(u8, parser.symbol().?, "LOOP"));
}

test "dest" {
    var parser = try Parser().init("./test/Test.asm", testing.io);
    parser.advance();
    try testing.expect(parser.symbol() == null);
    parser.advance();
    try testing.expect(std.mem.eql(u8, parser.dest().?, "D"));
    for (0..8) |_| {
        parser.advance();
    }
    try testing.expect(std.mem.eql(u8, parser.dest().?, "M"));
}

test "comp" {
    var parser = try Parser().init("./test/Test.asm", testing.io);
    parser.advance();
    try testing.expect(parser.comp() == null);
    parser.advance();
    try testing.expect(std.mem.eql(u8, parser.comp().?, "M"));
    for (0..12) |_| {
        parser.advance();
    }
    try testing.expect(std.mem.eql(u8, parser.comp().?, "-1"));
    for (0..4) |_| {
        parser.advance();
    }
    try testing.expect(std.mem.eql(u8, parser.comp().?, "D+A"));
}

test "jump" {
    var parser = try Parser().init("./test/Test.asm", testing.io);
    for (0..3) |_| {
        parser.advance();
        try testing.expect(parser.jump() == null);
    }
    parser.advance();
    try testing.expect(std.mem.eql(u8, parser.jump().?, "JLE"));
    for (0..19) |_| {
        parser.advance();
        try testing.expect(parser.jump() == null);
    }
    parser.advance();
    try testing.expect(std.mem.eql(u8, parser.jump().?, "JGT"));
    for (0..2) |_| {
        parser.advance();
        try testing.expect(parser.jump() == null);
    }
    parser.advance();
    try testing.expect(std.mem.eql(u8, parser.jump().?, "JMP"));
}
