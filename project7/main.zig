const std = @import("std");

const CommandType = enum(const[] u8) {
    C_ARITHMETIC = "arithmetic",
    C_CALL = "call",
    C_FUNCTION = "function",
    C_GOTO = "goto",
    C_IF = "if",
    C_LABEL = "label",
    C_POP = "pop",
    C_PUSH = "push",
    C_RETURN = "return",
};

pub fn main(init: std.process.Init) !void {
    const stdout = std.Io.File.stdout();
    const command = "label";
    try stdout.writeStreamingAll(init.io, std.meta.stringToEnum(command));
}
