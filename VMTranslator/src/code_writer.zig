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

const LABEL_SIZE: usize = 5;

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

    pub fn init(io: std.Io, allocator: mem.Allocator) !Self {
        var baseAddrTable = try BaseAddressMap.init(allocator);
        errdefer baseAddrTable.deinit();

        return Self{
            .allocator = allocator,
            .instructions = try .initCapacity(allocator, 512),
            .baseAddrTable = baseAddrTable,
            .outputPath = undefined,
            .rng = .{ .io = io },
            .instructionCount = 0,
            .symbolTable = StringHashMap(usize).init(allocator),
            .symbolReferences = .empty,
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

    pub fn setFileName(self: *Self, outputPath: []const u8) void {
        self.outputPath = outputPath;
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
                const label = try self.generateRandomLabel(self.allocator);
                defer self.allocator.free(label);

                const jumpType = switch (compare) {
                    .Eq => "JEQ",
                    .Lt => "JLT",
                    .Gt => "JGT",
                    else => unreachable,
                };
                break :blk try std.fmt.allocPrint(self.allocator, tmpl.CompareOperation, .{ label, jumpType });
            },
        };

        try self.instructions.append(self.allocator, buf);
        self.instructionCount += mem.count(u8, buf, "\n") + 1;
    }

    /// Generate a random label to be embbed in the output code. Caller owns the label
    fn generateRandomLabel(self: Self, allocator: mem.Allocator) ![]const u8 {
        const iRng = self.rng.interface();

        var label = try allocator.alloc(u8, LABEL_SIZE);
        for (0..LABEL_SIZE) |i| {
            label[i] = iRng.intRangeAtMost(u8, 'a', 'z');
        }
        return label;
    }

    pub fn writePushPop(self: *Self, commandType: CommandType, segment: SegmentType, index: u16) !void {
        var buf: []u8 = undefined;
        switch (commandType) {
            .C_PUSH => {
                switch (segment) {
                    .LCL, .ARG, .This, .That => {
                        const pAddr: u8 = switch (segment) {
                            .LCL => '1',
                            .ARG => '2',
                            .This, .Pointer => '3',
                            .That => '4',
                            else => unreachable,
                        };
                        buf = try std.fmt.allocPrint(self.allocator, tmpl.PushVirtual, .{ index, pAddr });
                    },
                    else => { // .Static, .Temp, .Pointer
                        const baseAddr = self.baseAddrTable.get(segment).?;
                        const addrOffset = baseAddr + index;
                        const source: u8 = if (segment == .Constant) 'A' else 'M';
                        buf = try std.fmt.allocPrint(self.allocator, tmpl.PushVirtual, .{ addrOffset, source });
                    },
                }
            },
            .C_POP => {
                switch (segment) {
                    .LCL, .ARG, .This, .That => {
                        const pAddr: u8 = switch (segment) {
                            .LCL => '1',
                            .ARG => '2',
                            .This, .Pointer => '3',
                            .That => '4',
                            else => unreachable,
                        };
                        buf = try std.fmt.allocPrint(self.allocator, tmpl.PopVirtual, .{ index, pAddr });
                    },
                    else => { // .Static, .Temp, .Pointer
                        const baseAddr = self.baseAddrTable.get(segment).?;
                        const addrOffset = baseAddr + index;
                        buf = try std.fmt.allocPrint(self.allocator, tmpl.Pop, .{addrOffset});
                    },
                }
            },
            else => {
                return;
            },
        }
        try self.instructions.append(self.allocator, buf);
        self.instructionCount += mem.count(u8, buf, "\n") + 1;
    }

    pub fn writeLabel(self: *Self, label: []const u8) !void {
        const fullLabel = try fmt.allocPrint(self.allocator, "{s}", .{label});

        if (self.symbolTable.get(fullLabel)) |_| {
            return CodeWriterError.LabelRedeclaration;
        }
        try self.symbolTable.put(fullLabel, self.instructionCount);
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
        const fullLabel = try fmt.allocPrint(self.allocator, "{s}", .{label});
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
        try self.writeLabel(functionName);

        // Initialize 'numLocals' local variables to 0
        for (0..numLocals) |_| {
            try self.writePushPop(.C_PUSH, .LCL, 0);
        }
    }

    pub fn writeReturn(self: *Self) !void {
        try self.instructions.append(self.allocator, try self.allocator.dupe(u8, tmpl.Return));
        self.instructionCount += mem.count(u8, tmpl.Return, "\n") + 1;
    }

    pub fn writeCall(self: *Self, functionName: []const u8, numArgs: usize) !void {
        const returnLabel = try self.generateRandomLabel(self.allocator);

        const buf = try fmt.allocPrint(self.allocator, tmpl.Call, .{ returnLabel, numArgs, functionName });
        try self.instructions.append(self.allocator, buf);
        self.instructionCount += mem.count(u8, tmpl.Call, "\n") + 1;

        try self.symbolReferences.append(self.allocator, .{ .label = returnLabel, .index = self.instructions.items.len - 1 });
        try self.symbolReferences.append(self.allocator, .{ .label = try self.allocator.dupe(u8, functionName), .index = self.instructions.items.len - 1 });

        try self.writeLabel(returnLabel);
    }

    /// Uses the built list of instructions with symbolic references, and
    /// uses a lookup to resolve those symbols to addresses in ROM
    fn resolveSymbols(self: *Self) !void {
        for (self.symbolReferences.items) |item| {
            const romAddr = self.symbolTable.get(item.label) orelse {
                return CodeWriterError.UnresolvedLabel;
            };

            const template: []const u8 = self.instructions.items[item.index];
            defer self.allocator.free(template);

            // usize to []const u8
            const romAddrStr = try fmt.allocPrint(self.allocator, "{d}", .{romAddr});
            defer self.allocator.free(romAddrStr);

            // replace the label with the actual ROM address
            const buf = try mem.replaceOwned(u8, self.allocator, template, item.label, romAddrStr);
            self.instructions.items[item.index] = buf;
        }
    }

    pub fn close(self: *Self, io: std.Io) !void {
        try self.resolveSymbols();

        const output = try mem.join(self.allocator, "\n", self.instructions.items);
        defer self.allocator.free(output);

        const outputFile = try std.Io.Dir.cwd().createFile(io, self.outputPath, .{ .read = false });
        defer outputFile.close(io);

        try outputFile.writeStreamingAll(io, output);
    }
};

test "smoke" {
    var cw = try CodeWriter.init(testing.io, testing.allocator);
    defer cw.deinit();

    try testing.expect(cw.instructions.items.len == 0);
}

test "writePushPop" {
    var cw = try CodeWriter.init(testing.io, testing.allocator);
    defer cw.deinit();

    try cw.writePushPop(.C_PUSH, .Constant, 10);
    try testing.expectEqual(cw.instructions.items.len, 1);
    try cw.writePushPop(.C_POP, .LCL, 0);
    try testing.expectEqual(cw.instructions.items.len, 2);

    for (cw.instructions.items) |item| {
        // While not worried about testing the instruction implementation,
        // POP/PUSH should have at least one reference to 'SP' and should
        // also be valid memory (i.e. not segfaulting on access)
        try testing.expect(mem.count(u8, item, "SP") > 0);
    }
}

test "writeArithmetic" {
    var cw = try CodeWriter.init(testing.io, testing.allocator);
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
    var cw = try CodeWriter.init(testing.io, testing.allocator);
    defer cw.deinit();

    const filename = "./test/test_output.asm";
    cw.setFileName(filename);
    try cw.writePushPop(.C_PUSH, .Constant, 42);
    try cw.writePushPop(.C_PUSH, .Constant, 27);
    try cw.writeArithmetic(.Add);
    try cw.close(testing.io);

    const file = try std.Io.Dir.cwd().openFile(testing.io, filename, .{ .mode = .read_only });
    defer file.close(testing.io);
    defer std.Io.Dir.cwd().deleteFile(testing.io, filename) catch {
        std.debug.print("Failed to delete test file: {s}\n", .{filename});
    };

    try testing.expect(try file.length(testing.io) > 0);
}

test "writeInit" {
    var cw = try CodeWriter.init(testing.io, testing.allocator);
    defer cw.deinit();

    try cw.writeInit();
    const instruction = cw.instructions.getLast().?;
    try testing.expect(mem.count(u8, instruction, "@SP") > 0);
    try testing.expect(mem.count(u8, instruction, "@LCL") > 0);
    try testing.expect(mem.count(u8, instruction, "@ARG") > 0);
}

test "writeLabel" {
    var cw = try CodeWriter.init(testing.io, testing.allocator);
    defer cw.deinit();

    try cw.writeInit();
    try cw.writeLabel("Sys.init");
    try cw.writePushPop(.C_PUSH, .Constant, 42);
    try cw.writePushPop(.C_PUSH, .Constant, 27);
    try cw.writeArithmetic(.Add);
    try testing.expectEqual(cw.symbolTable.get("Sys.init"), 14);
}
