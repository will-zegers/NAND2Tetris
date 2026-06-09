const std = @import("std");
const testing = std.testing;

const BinaryOp = struct {
    const Self = @This();
    const prelude =
        \\@SP
        \\AM=M-1
        \\D=M
        \\A=A-1
        \\{s}
        \\
    ;

    operation: []const u8,

    fn init(operation: []const u8) Self {
        return Self{
            .operation = operation,
        };
    }

    pub fn fmt(self: Self, buffer: []u8) ![]const u8 {
        return std.fmt.bufPrint(buffer[0..], prelude, .{self.operation}) catch |err| {
            return err;
        };
    }
};

const Unary = struct {
    const Self = @This();
    const prelude =
        \\@SP
        \\A=M-1
        \\{s}
        \\
    ;

    operation: []const u8,

    fn init(operation: []const u8) Self {
        return Self{
            .operation = operation,
        };
    }

    pub fn fmt(self: Self, buffer: []u8) ![]const u8 {
        return std.fmt.bufPrint(buffer[0..], prelude, .{self.operation}) catch |err| {
            return err;
        };
    }
};

var index: u8 = 'A';

const Comparison = struct {
    const Self = @This();
    const template =
        \\@SP
        \\AM=M-1
        \\D=M
        \\A=A-1
        \\D=M-D
        \\@{c}
        \\D;{s}
        \\  @SP
        \\  A=M-1
        \\  M=0
        \\  @End{c}
        \\  0;JMP
        \\({c})
        \\  @SP
        \\  A=M-1
        \\  M=-1
        \\(End{c})
        \\
    ;

    operation: []const u8,

    fn init(jumpType: []const u8) Self {
        return Self{
            .operation = operation,
        };
    }

    pub fn fmt(self: Self, buffer: []u8) ![]const u8 {
        defer index += 1;
        return std.fmt.bufPrint(buffer[0..], template, .{ index, self.jumpType, index, index, index }) catch |err| {
            return err;
        };
    }
};

pub const Add = BinaryOp.init("M=D+M");
pub const Sub = BinaryOp.init("M=M-D");
pub const Or = BinaryOp.init("M=D|M");
pub const And = BinaryOp.init("M=D&M");
pub const Neg = Unary.init("M=-M");
pub const Not = Unary.init("M=!M");
pub const EQ = Comparison.init("JEQ");
pub const LT = Comparison.init("JLT");
pub const GT = Comparison.init("JGT");
