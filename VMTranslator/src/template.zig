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

pub const Push =
    \\@{d}
    \\D={c}
    \\@SP
    \\A=M
    \\M=D
    \\@SP
    \\M=M+1
;

pub const PushMemory =
    \\@{d}
    \\D=A
    \\@{c}
    \\D=D+M
    \\A=D
    \\D=M
    \\@SP
    \\A=M
    \\M=D
    \\@SP
    \\M=M+1
;

pub const Pop =
    \\@SP
    \\AM=M-1
    \\D=M
    \\@{d}
    \\M=D
;

pub const PopMemory =
    \\@{d}
    \\D=A
    \\@{c}
    \\D=D+M
    \\@SP
    \\AM=M-1
    \\D=D+M
    \\A=D-M
    \\D=D-A
    \\M=D
;

pub const Goto =
    \\@{s}
    \\0;JMP
;

pub const IfGoto =
    \\@SP
    \\AM=M-1
    \\D=M
    \\@{s}
    \\D;JNE
;

pub const Return =
    // Save the return address to a temporary register
    \\@5
    \\D=A
    \\@LCL
    \\A=M
    \\A=A-D
    \\D=M
    \\@R13
    \\M=D
    // Pop the return value into ARG[0] (which will be the top of the caller's stack)
    \\@0
    \\A=M-1
    \\D=M
    \\@ARG
    \\A=M
    \\M=D
    // Restore the stack pointer of the caller
    \\A=A+1
    \\D=A
    \\@SP
    \\M=D
    // Restore the THAT pointer
    \\@1
    \\D=A
    \\@LCL
    \\D=M-D
    \\A=D
    \\D=M
    \\@THAT
    \\M=D
    // Restore the THIS pointer
    \\@2
    \\D=A
    \\@LCL
    \\D=M-D
    \\A=D
    \\D=M
    \\@THIS
    \\M=D
    // Restore the ARG pointer
    \\@3
    \\D=A
    \\@LCL
    \\D=M-D
    \\A=D
    \\D=M
    \\@ARG
    \\M=D
    // Restore the LCL pointer
    \\@4
    \\D=A
    \\@LCL
    \\D=M-D
    \\A=D
    \\D=M
    \\@LCL
    \\M=D
    // Jump to the caller's return address
    \\@R13
    \\A=M
    \\0;JMP
;

pub const Call =
    // Push the return address
    \\@{s}
    \\D=A
    \\@0
    \\A=M
    \\M=D
    \\@0
    \\M=M+1
    // Push LCL pointer
    \\@LCL
    \\D=M
    \\@0
    \\A=M
    \\M=D
    \\@0
    \\M=M+1
    // Push ARG pointer
    \\@ARG
    \\D=M
    \\@0
    \\A=M
    \\M=D
    \\@0
    \\M=M+1
    // Push THIS pointer
    \\@THIS
    \\D=M
    \\@0
    \\A=M
    \\M=D
    \\@0
    \\M=M+1
    // Push THAT pointer
    \\@THAT
    \\D=M
    \\@0
    \\A=M
    \\M=D
    \\@0
    \\M=M+1
    // Set the ARG pointer for the callee (ARG = SP - numArgs - 5 [pointers just pushed to stack])
    \\@{d}
    \\D=A
    \\@5
    \\D=D+A
    \\@SP
    \\D=M-D
    \\@ARG
    \\M=D
    // Set LCL to the top of the stack
    \\@SP
    \\D=M
    \\@LCL
    \\M=D
    // Jump to function address
    \\@{s}
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
