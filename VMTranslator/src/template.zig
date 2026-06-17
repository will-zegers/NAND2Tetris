pub const Bootstrap =
    \\@256
    \\D=A
    \\@SP
    \\M=D
    \\@300
    \\D=A
    \\@LCL
    \\M=D
    \\@400
    \\D=A
    \\@ARG
    \\M=D
    \\@Sys.init
    \\0;JMP
;

pub const UnaryOperation =
    \\@SP
    \\A=M-1
    \\{s}
;

pub const BinaryOperation =
    \\@SP
    \\AM=M-1
    \\D=M
    \\A=A-1
    \\{s}
;

pub const CompareOperation =
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
