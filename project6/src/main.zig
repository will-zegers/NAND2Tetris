const std = @import("std");
const expect = std.testing.expect;

const DESTS_FILE = "dests.txt";
const COMPS_FILE = "comps.txt";
const JUMPS_FILE = "jumps.txt";

const BUFFER_SIZE = 1024;

pub fn main(init: std.process.Init) !void {
    var iterator =
        try init.minimal.args.iterateAllocator(
            init.gpa,
        );
    defer iterator.deinit();

    _ = iterator.skip(); // skip the program name
    const input_path = iterator.next() orelse "MaxL.asm";
    var it = std.mem.splitScalar(u8, input_path, '.');
    const base_name = it.next() orelse unreachable;
    const output_path = std.fmt.allocPrint(init.gpa, "{s}.hack", .{base_name}) catch unreachable;
    defer init.gpa.free(output_path);

    var comp_buf: [BUFFER_SIZE]u8 = undefined;
    var dest_buf: [BUFFER_SIZE]u8 = undefined;
    var jump_buf: [BUFFER_SIZE]u8 = undefined;
    var read_buf: [BUFFER_SIZE]u8 = undefined;

    var comps_map = try hashmap_from_file(init.io, COMPS_FILE, &comp_buf);
    var dests_map = try hashmap_from_file(init.io, DESTS_FILE, &dest_buf);
    var jumps_map = try hashmap_from_file(init.io, JUMPS_FILE, &jump_buf);

    const cwd = std.Io.Dir.cwd();
    const input_file = try cwd.openFile(init.io, input_path, .{ .mode = .read_only });
    defer input_file.close(init.io);
    const output_file = try cwd.createFile(init.io, output_path, .{ .read = false });
    defer output_file.close(init.io);

    var fr = input_file.reader(init.io, &read_buf);
    var reader = &fr.interface;
    const bytes_read = reader.readSliceShort(&read_buf) catch 0;
    var instructions = std.mem.splitScalar(u8, read_buf[0 .. bytes_read - 1], '\n');

    var machine_fmt: [17]u8 = undefined; // 16 bits + newline
    while (instructions.next()) |instruction| {
        if (std.mem.startsWith(u8, instruction, "//")) {
            continue;
        }

        if (instruction.len == 0) {
            continue;
        }

        if (std.mem.startsWith(u8, instruction, "@")) {
            const value = instruction[1..instruction.len];
            const num_value = try std.fmt.parseInt(u16, value, 10);

            _ = try std.fmt.bufPrint(&machine_fmt, "{b:0>16}\n", .{num_value});
        } else {
            var comp: []const u8 = undefined;
            var dest_machine: []const u8 = "000";
            var jump_machine: []const u8 = "000";

            const split_char: u8 = get_split_char(instruction);
            var ins = std.mem.splitScalar(u8, instruction, split_char);

            if (split_char == ';') { // if it's a jump instruction, then it's comp;jump
                comp = ins.next() orelse unreachable;
                const jump = ins.next() orelse unreachable;
                jump_machine = jumps_map.get(jump) orelse unreachable;
            } else { // else it's a dest=comp instruction
                const dest = ins.next() orelse unreachable;
                comp = ins.next() orelse unreachable;
                dest_machine = dests_map.get(dest) orelse unreachable;
            }

            const a = get_a_bit(comp);
            const comp_machine = comps_map.get(comp) orelse unreachable;

            _ = try std.fmt.bufPrint(&machine_fmt, "111{c}{s}{s}{s}\n", .{ a, comp_machine, dest_machine, jump_machine });
        }

        const length = try output_file.length(init.io);
        _ = try output_file.writePositionalAll(init.io, &machine_fmt, length);
    }
}

fn get_a_bit(comp: []const u8) u8 {
    for (comp) |c| {
        if (c == 'M') {
            return '1';
        }
    }
    return '0';
}

fn get_split_char(instruction: []const u8) u8 {
    if (is_jump_instruction(instruction)) {
        return ';';
    } else {
        return '=';
    }
}

fn is_jump_instruction(instruction: []const u8) bool {
    for (instruction) |c| {
        if (c == ';') {
            return true;
        }
    }
    return false;
}

fn hashmap_from_file(io: std.Io, filename: []const u8, buffer: []u8) !std.StringHashMap([]const u8) {
    const file = try std.Io.Dir.cwd().openFile(io, filename, .{ .mode = .read_only });
    defer file.close(io);

    var map = std.StringHashMap([]const u8).init(std.heap.page_allocator);

    var fr = file.reader(io, buffer);
    var reader = &fr.interface;
    const bytes_read = reader.readSliceShort(buffer) catch 0;
    var lines = std.mem.splitScalar(u8, buffer[0 .. bytes_read - 1], '\n');

    while (lines.next()) |line| {
        var key_val = std.mem.splitScalar(u8, line, ':');
        const symbol = key_val.next() orelse unreachable;
        const machine = key_val.next() orelse unreachable;
        _ = try map.put(symbol, machine);
    }

    return map;
}
