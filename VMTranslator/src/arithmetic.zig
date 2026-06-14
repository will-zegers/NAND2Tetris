pub const UnaryTemplate =
    \\@SP
    \\A=M-1
    \\{s}
;

pub const BinaryTemplate =
    \\@SP
    \\AM=M-1
    \\D=M
    \\A=A-1
    \\{s}
;

pub const CompareTemplate =
    \\@SP
    \\AM=M-1
    \\D=M
    \\A=A-1
    \\D=M-D
    \\@{0s}
    \\D;{1s}
    \\  @SP
    \\  A=M-1
    \\  M=0
    \\  @end_{0s}
    \\  0;JMP
    \\({0s})
    \\  @SP
    \\  A=M-1
    \\  M=-1
    \\(end_{0s})
;
