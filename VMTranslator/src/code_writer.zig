const std = @import("std");
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;
const Random = std.Random;
const StringHashMap = std.StringHashMap;
const fmt = std.fmt;
const mem = std.mem;
const testing = std.testing;

const util = @import("util.zig");

const arithmetic = @import("arithmetic.zig");
const UnaryTemplate = arithmetic.UnaryTemplate;
const BinaryTemplate = arithmetic.BinaryTemplate;
const CompareTemplate = arithmetic.CompareTemplate;

const mAddress = @import("map/address.zig");
const BaseAddressMap = mAddress.BaseAddressMap;

const mCommand = @import("map/command.zig");
const CommandType = mCommand.CommandType;

const mOperation = @import("map/operation.zig");
const OperationType = mOperation.OperationType;

const mSegment = @import("map/segment.zig");
const SegmentType = mSegment.SegmentType;

const tmpl = @import("template.zig");

const TAG_SIZE: usize = 5;

const CodeWriterError = error{
    UnresolvedLabel,
    LabelRedeclaration,
};

const SymbolReference = struct {
    index: usize, // instruction index
    label: []const u8,
};

pub const CodeWriter = struct {
    const Self = @This();

    allocator: mem.Allocator,
    instructions: ArrayList([]const u8),
    baseAddrTable: BaseAddressMap,
    outputPath: []const u8,
    rng: Random.IoSource,
    instructionCount: usize,
    symbolTable: StringHashMap(usize),
    symbolReferences: ArrayList(SymbolReference),
    staticNamespace: ?[]const u8,
    subroutineNamespace: ?[]const u8,

    pub fn init(io: std.Io, allocator: mem.Allocator, outputPath: []const u8) !Self {
        var baseAddrTable = try BaseAddressMap.init(allocator);
        errdefer baseAddrTable.deinit();

        return Self{
            .allocator = allocator,
            .instructions = try .initCapacity(allocator, 512),
            .baseAddrTable = baseAddrTable,
            .outputPath = outputPath,
            .rng = .{ .io = io },
            .instructionCount = 0,
            .symbolTable = StringHashMap(usize).init(allocator),
            .symbolReferences = .empty,
            .staticNamespace = null,
            .subroutineNamespace = null,
        };
    }

    pub fn deinit(self: *Self) void {
        defer self.instructions.deinit(self.allocator);
        defer self.symbolReferences.deinit(self.allocator);
        defer self.baseAddrTable.deinit();
        defer self.symbolTable.deinit();

        for (self.instructions.items) |item| {
            self.allocator.free(item);
        }

        var kit = self.symbolTable.keyIterator();
        while (kit.next()) |key| {
            self.allocator.free(key.*);
        }

        for (self.symbolReferences.items) |item| {
            self.allocator.free(item.label);
        }
    }

    pub fn setFileName(self: *Self, filename: []const u8) void {
        var vmFilename: []const u8 = undefined;

        // Remove '/' upto the top level file
        var it = mem.splitScalar(u8, filename, '/');
        while (it.next()) |item| {
            vmFilename = item;
        }

        // Remove the .vm extension and set the static context
        it = mem.splitScalar(u8, vmFilename, '.');
        self.staticNamespace = it.first();
    }

    pub fn writeInit(self: *Self) !void {
        try self.instructions.append(self.allocator, try self.allocator.dupe(u8, tmpl.Bootstrap));
        self.instructionCount += mem.count(u8, tmpl.Bootstrap, "\n") + 1;

        try self.symbolReferences.append(self.allocator, .{ .label = try self.allocator.dupe(u8, "Sys.init"), .index = 0 });
    }
    pub fn writeArithmetic(self: *Self, operation: OperationType) !void {
        const buf: []const u8 = switch (operation) {
            .Add => try fmt.allocPrint(self.allocator, tmpl.BinaryOperation, .{"M=D+M"}),
            .Sub => try fmt.allocPrint(self.allocator, tmpl.BinaryOperation, .{"M=M-D"}),
            .And => try fmt.allocPrint(self.allocator, tmpl.BinaryOperation, .{"M=D&M"}),
            .Or => try fmt.allocPrint(self.allocator, tmpl.BinaryOperation, .{"M=D|M"}),
            .Neg => try fmt.allocPrint(self.allocator, tmpl.UnaryOperation, .{"M=-M"}),
            .Not => try fmt.allocPrint(self.allocator, tmpl.UnaryOperation, .{"M=!M"}),
            .Eq, .Lt, .Gt => |compare| blk: {
                const tag = try self.generateRandomTag(self.allocator);
                defer self.allocator.free(tag);

                const jumpType = switch (compare) {
                    .Eq => "JEQ",
                    .Lt => "JLT",
                    .Gt => "JGT",
                    else => unreachable,
                };
                break :blk try std.fmt.allocPrint(self.allocator, tmpl.CompareOperation, .{ tag, jumpType });
            },
        };

        try self.instructions.append(self.allocator, buf);
        self.instructionCount += mem.count(u8, buf, "\n") + 1;
    }

    /// Generate a random label to be embbed in the output code. Caller owns the label
    fn generateRandomTag(self: Self, allocator: mem.Allocator) ![]const u8 {
        const iRng = self.rng.interface();

        var tag = try allocator.alloc(u8, TAG_SIZE);
        for (0..TAG_SIZE) |i| {
            tag[i] = iRng.intRangeAtMost(u8, 'a', 'z');
        }
        return tag;
    }

    pub fn writePushPop(self: *Self, commandType: CommandType, segment: SegmentType, index: u16) !void {
        switch (commandType) {
            .C_PUSH => {
                try self.writePush(segment, index);
            },
            .C_POP => {
                try self.writePop(segment, index);
            },
            else => unreachable,
        }
    }

    fn writePush(self: *Self, segment: SegmentType, index: usize) !void {
        var buf: []u8 = undefined;
        switch (segment) {
            .Local, .Argument, .This, .That => {
                const pAddr: u8 = switch (segment) {
                    .Local => '1',
                    .Argument => '2',
                    .This, .Pointer => '3',
                    .That => '4',
                    else => unreachable,
                };
                buf = try std.fmt.allocPrint(self.allocator, tmpl.PushMemory, .{ index, pAddr });
            },
            .Static => {
                buf = try fmt.allocPrint(self.allocator, tmpl.PushStatic, .{ self.staticNamespace.?, index });
            },
            else => { // .Temp, .Pointer
                const baseAddr = self.baseAddrTable.get(segment).?;
                const addrOffset = baseAddr + index;
                const source: u8 = if (segment == .Constant) 'A' else 'M';
                buf = try std.fmt.allocPrint(self.allocator, tmpl.Push, .{ addrOffset, source });
            },
        }
        try self.instructions.append(self.allocator, buf);
        self.instructionCount += mem.count(u8, buf, "\n") + 1;
    }

    fn writePop(self: *Self, segment: SegmentType, index: usize) !void {
        var buf: []u8 = undefined;
        switch (segment) {
            .Local, .Argument, .This, .That => {
                const pAddr: u8 = switch (segment) {
                    .Local => '1',
                    .Argument => '2',
                    .This, .Pointer => '3',
                    .That => '4',
                    else => unreachable,
                };
                buf = try std.fmt.allocPrint(self.allocator, tmpl.PopMemory, .{ index, pAddr });
            },
            .Static => {
                buf = try fmt.allocPrint(self.allocator, tmpl.PopStatic, .{ self.staticNamespace.?, index });
            },
            else => { // .Temp, .Pointer
                const baseAddr = self.baseAddrTable.get(segment).?;
                const addrOffset = baseAddr + index;
                buf = try std.fmt.allocPrint(self.allocator, tmpl.Pop, .{addrOffset});
            },
        }
        try self.instructions.append(self.allocator, buf);
        self.instructionCount += mem.count(u8, buf, "\n") + 1;
    }

    pub fn writeLabel(self: *Self, label: []const u8) !void {
        try self.createLabelEntry(label, self.subroutineNamespace);
    }

    fn createLabelEntry(self: *Self, label: []const u8, subroutineNamespace: ?[]const u8) !void {
        const labelKey = if (subroutineNamespace) |ctx|
            try fmt.allocPrint(self.allocator, "{s}${s}", .{ ctx, label })
        else
            try fmt.allocPrint(self.allocator, "{s}", .{label});

        const labelI = try fmt.allocPrint(self.allocator, "({s})", .{labelKey});
        try self.instructions.append(self.allocator, labelI);
        self.instructionCount += 1;

        if (self.symbolTable.get(labelKey)) |_| {
            return CodeWriterError.LabelRedeclaration;
        }
        try self.symbolTable.put(labelKey, self.instructionCount);
    }

    pub fn writeGoto(self: *Self, label: []const u8) !void {
        try self.writeGotoOrIf(label, tmpl.Goto);
    }

    pub fn writeIf(self: *Self, label: []const u8) !void {
        try self.writeGotoOrIf(label, tmpl.IfGoto);
    }

    /// Handles the bulk of writing 'goto' and 'if-goto' instructions, and
    /// depends only on the assembly implementation of either
    fn writeGotoOrIf(self: *Self, label: []const u8, comptime template: []const u8) !void {
        const fullLabel = try fmt.allocPrint(self.allocator, "{s}${s}", .{ self.subroutineNamespace.?, label });
        defer self.allocator.free(fullLabel);

        const buf = try fmt.allocPrint(self.allocator, template, .{fullLabel});
        try self.instructions.append(self.allocator, buf);
        self.instructionCount += mem.count(u8, template, "\n") + 1;

        // add this instruction as an entry in symbol references, to be resolved
        // once all labels have been declared and can be mapped to addresses
        const entry: SymbolReference = .{ .label = try self.allocator.dupe(u8, fullLabel), .index = self.instructions.items.len - 1 };
        try self.symbolReferences.append(self.allocator, entry);
    }

    pub fn writeFunction(self: *Self, functionName: []const u8, numLocals: usize) !void {
        try self.createLabelEntry(functionName, null);
        self.subroutineNamespace = functionName;

        // Initialize 'numLocals' local variables to 0
        for (0..numLocals) |_| {
            try self.writePushPop(.C_PUSH, .Local, 0);
        }
    }

    pub fn writeReturn(self: *Self) !void {
        try self.instructions.append(self.allocator, try self.allocator.dupe(u8, tmpl.Return));
        self.instructionCount += mem.count(u8, tmpl.Return, "\n") + 1;
    }

    pub fn writeCall(self: *Self, functionName: []const u8, numArgs: usize) !void {
        const returnTag = try self.generateRandomTag(self.allocator);
        defer self.allocator.free(returnTag);
        const returnLabel = try fmt.allocPrint(self.allocator, "{s}${s}", .{ self.subroutineNamespace.?, returnTag });

        const buf = try fmt.allocPrint(self.allocator, tmpl.Call, .{ returnLabel, numArgs, functionName });
        try self.instructions.append(self.allocator, buf);
        self.instructionCount += mem.count(u8, tmpl.Call, "\n") + 1;

        const index = self.instructions.items.len - 1;
        try self.symbolReferences.append(self.allocator, .{ .label = returnLabel, .index = index });
        try self.symbolReferences.append(self.allocator, .{ .label = try self.allocator.dupe(u8, functionName), .index = index });

        try self.createLabelEntry(returnLabel, null);
    }

    pub fn close(self: *Self, io: std.Io) !void {
        const output = try mem.join(self.allocator, "\n", self.instructions.items);
        defer self.allocator.free(output);

        const outputFile = try std.Io.Dir.cwd().createFile(io, self.outputPath, .{ .read = false });
        defer outputFile.close(io);

        try outputFile.writeStreamingAll(io, output);
    }
};

test "smoke" {
    var cw = try CodeWriter.init(testing.io, testing.allocator, "Test.asm");
    defer cw.deinit();

    try testing.expectEqual(cw.instructions.items.len, 0);
    try testing.expectEqual(cw.instructionCount, 0);
    try testing.expectEqual(cw.staticNamespace, null);
    try testing.expectEqual(cw.subroutineNamespace, null);
}

test "writePushPop" {
    var cw = try CodeWriter.init(testing.io, testing.allocator, "test/Test.asm");
    defer cw.deinit();

    try cw.writePushPop(.C_PUSH, .Constant, 10);
    try testing.expectEqual(cw.instructions.items.len, 1);
    try cw.writePushPop(.C_POP, .Local, 0);
    try testing.expectEqual(cw.instructions.items.len, 2);

    for (cw.instructions.items) |item| {
        // While not worried about testing the instruction implementation,
        // POP/PUSH should have at least one reference to 'SP' and should
        // also be valid memory (i.e. not segfaulting on access)
        try testing.expect(mem.count(u8, item, "SP") > 0);
    }
}

test "writeArithmetic" {
    var cw = try CodeWriter.init(testing.io, testing.allocator, "test/Test.asm");
    defer cw.deinit();

    try cw.writeArithmetic(.Add);
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "D+M") > 0);
    try cw.writeArithmetic(.Sub);
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "M-D") > 0);
    try cw.writeArithmetic(.And);
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "D&M") > 0);
    try cw.writeArithmetic(.Or);
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "D|M") > 0);
    try cw.writeArithmetic(.Neg);
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "-M") > 0);
    try cw.writeArithmetic(.Not);
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "!M") > 0);
    try cw.writeArithmetic(.Eq);
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "JEQ") > 0);
    try cw.writeArithmetic(.Lt);
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "JLT") > 0);
    try cw.writeArithmetic(.Gt);
    try testing.expect(mem.count(u8, cw.instructions.getLast().?, "JGT") > 0);
}

test "setFileName and close" {
    const outputPath = "test/Test.asm";
    var cw = try CodeWriter.init(testing.io, testing.allocator, outputPath);
    defer cw.deinit();

    cw.setFileName("test/Test.vm");
    try testing.expectEqualStrings("Test", cw.staticNamespace.?);
    try cw.writePushPop(.C_PUSH, .Constant, 42);
    try cw.writePushPop(.C_PUSH, .Constant, 27);
    try cw.writeArithmetic(.Add);
    try cw.close(testing.io);

    const file = try std.Io.Dir.cwd().openFile(testing.io, outputPath, .{ .mode = .read_only });
    defer file.close(testing.io);
    defer std.Io.Dir.cwd().deleteFile(testing.io, outputPath) catch {
        std.debug.print("Failed to delete test file: {s}\n", .{outputPath});
    };

    try testing.expect(try file.length(testing.io) > 0);
}

test "writeInit" {
    var cw = try CodeWriter.init(testing.io, testing.allocator, "test/Test.asm");
    defer cw.deinit();

    try cw.writeInit();
    const instruction = cw.instructions.getLast().?;
    try testing.expect(mem.count(u8, instruction, "@SP") > 0);
    try testing.expect(mem.count(u8, instruction, "@LCL") > 0);
    try testing.expect(mem.count(u8, instruction, "@ARG") > 0);
}

test "writeLabel" {
    var cw = try CodeWriter.init(testing.io, testing.allocator, "test/Test.asm");
    defer cw.deinit();

    try cw.writeInit();
    try cw.writeLabel("Sys.init");
    try cw.writePushPop(.C_PUSH, .Constant, 42);
    try cw.writePushPop(.C_PUSH, .Constant, 27);
    try cw.writeArithmetic(.Add);
    try testing.expectEqual(cw.symbolTable.get("Sys.init"), 15);
}

test "writeFunction" {
    var cw = try CodeWriter.init(testing.io, testing.allocator, "test/Test.asm");
    defer cw.deinit();

    try cw.writeInit();
    try cw.writeFunction("Sys.init", 3);
    try cw.writePushPop(.C_PUSH, .Constant, 42);
    try cw.writePushPop(.C_PUSH, .Constant, 27);
    try cw.writeArithmetic(.Add);

    try testing.expectEqualStrings(cw.instructions.items[1], "(Sys.init)");
    // Three local variables, push zero to initialize each one
    try testing.expectEqualStrings(cw.instructions.items[2], cw.instructions.items[3]);
    try testing.expectEqualStrings(cw.instructions.items[3], cw.instructions.items[4]);
}

test "writeGoto" {
    var cw = try CodeWriter.init(testing.io, testing.allocator, "test/Test.asm");
    defer cw.deinit();

    try cw.writeInit();
    try cw.writeFunction("Jump.here", 0);
    try cw.writePushPop(.C_PUSH, .Constant, 42);
    try cw.writePushPop(.C_PUSH, .Constant, 27);
    try cw.writeArithmetic(.Add);
    try cw.writeGoto("Jump.here");
    const goto = cw.instructions.getLast().?;
    try testing.expect(mem.count(u8, goto, "0;JMP") == 1);
}

test "writeIf" {
    var cw = try CodeWriter.init(testing.io, testing.allocator, "test/Test.asm");
    defer cw.deinit();

    try cw.writeInit();
    try cw.writeFunction("Maybe.jump", 0);
    try cw.writePushPop(.C_PUSH, .Constant, 42);
    try cw.writePushPop(.C_PUSH, .Constant, 27);
    try cw.writeArithmetic(.Add);
    try cw.writeIf("Maybe.jump");
    const goto = cw.instructions.getLast().?;
    try testing.expect(mem.count(u8, goto, "D;JNE") == 1);
}

test "writeReturn" {
    var cw = try CodeWriter.init(testing.io, testing.allocator, "test/Test.asm");
    defer cw.deinit();

    try cw.writeInit();
    try cw.writeFunction("Sys.init", 3);
    try cw.writePushPop(.C_PUSH, .Constant, 42);
    try cw.writePushPop(.C_PUSH, .Constant, 27);
    try cw.writeArithmetic(.Add);
    try cw.writeReturn();

    const returnInst = cw.instructions.getLast().?;
    try testing.expect(mem.count(u8, returnInst, "THAT") > 0);
    try testing.expect(mem.count(u8, returnInst, "THIS") > 0);
    try testing.expect(mem.count(u8, returnInst, "ARG") > 0);
    try testing.expect(mem.count(u8, returnInst, "LCL") > 0);
    try testing.expect(mem.count(u8, returnInst, "0;JMP") > 0);
}

test "writeCall" {
    var cw = try CodeWriter.init(testing.io, testing.allocator, "test/Test.asm");
    defer cw.deinit();

    try cw.writeInit();
    try cw.writeFunction("Sys.init", 3);
    try cw.writeCall("Sys.init", 3);

    const returnLbl = cw.instructions.pop().?;
    defer testing.allocator.free(returnLbl);

    const callInst = cw.instructions.pop().?;
    defer testing.allocator.free(callInst);

    try testing.expect(mem.startsWith(u8, returnLbl, "(Sys.init$"));

    try testing.expect(mem.count(u8, callInst, "THAT") > 0);
    try testing.expect(mem.count(u8, callInst, "THIS") > 0);
    try testing.expect(mem.count(u8, callInst, "ARG") > 0);
    try testing.expect(mem.count(u8, callInst, "LCL") > 0);
    try testing.expect(mem.count(u8, callInst, "0;JMP") > 0);
}
