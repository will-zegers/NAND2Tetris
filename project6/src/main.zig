const std = @import("std");

const DESTS_FILE = "dests.txt";
const COMPS_FILE = "comps.txt";
const JUMPS_FILE = "jumps.txt";

const MAP_BUFFER_SIZE = 1024;
const FILE_BUFFER_SIZE = 1024 * 1024;

pub fn main(init: std.process.Init) !void {
    var iterator =
        try init.minimal.args.iterateAllocator(
            init.gpa,
        );
    defer iterator.deinit();

    _ = iterator.skip(); // skip the program name
    const input_path = iterator.next();
    if (input_path == null) {
        std.debug.print("Usage: hack-assmbler <input_file.asm>\n", .{});
        return;
    }
    var it = std.mem.splitScalar(u8, input_path.?, '.');
    const base_name = it.next().?;
    const output_path = std.fmt.allocPrint(init.gpa, "{s}.hack", .{base_name}) catch unreachable;
    defer init.gpa.free(output_path);

    var comp_buf: [MAP_BUFFER_SIZE]u8 = undefined;
    var dest_buf: [MAP_BUFFER_SIZE]u8 = undefined;
    var jump_buf: [MAP_BUFFER_SIZE]u8 = undefined;
    var in_buf: [FILE_BUFFER_SIZE]u8 = undefined;
    var out_buf: [FILE_BUFFER_SIZE]u8 = undefined;

    var comps_map = try hashmap_from_file(init.io, init.gpa, COMPS_FILE, &comp_buf);
    defer comps_map.deinit();
    var dests_map = try hashmap_from_file(init.io, init.gpa, DESTS_FILE, &dest_buf);
    defer dests_map.deinit();
    var jumps_map = try hashmap_from_file(init.io, init.gpa, JUMPS_FILE, &jump_buf);
    defer jumps_map.deinit();

    const cwd = std.Io.Dir.cwd();
    const input_file = try cwd.openFile(init.io, input_path.?, .{ .mode = .read_only });
    defer input_file.close(init.io);

    var fr = input_file.reader(init.io, &in_buf);
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
    var instructions = std.mem.splitScalar(u8, in_buf[0 .. total_bytes - 1], '\n');

    var pc_value: usize = 0;
    var bytes_out: usize = 0;
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

            const buf = try std.fmt.bufPrint(out_buf[bytes_out..], "{b:0>16}\n", .{num_value});
            bytes_out += buf.len;
        } else {
            var comp: ?[]const u8 = undefined;
            var dest_machine: ?[]const u8 = "000";
            var jump_machine: ?[]const u8 = "000";

            const split_char: u8 = get_split_char(instruction);
            var ins = std.mem.splitScalar(u8, instruction, split_char);

            if (split_char == ';') { // if it's a jump instruction, then it's comp;jump
                comp = ins.next();
                const jump = ins.next();
                if (comp == null or jump == null) {
                    std.process.fatal("Error parsing instruction: {s}\n", .{instruction});
                }
                jump_machine = jumps_map.get(jump.?);
            } else { // else it's a dest=comp instruction
                const dest = ins.next();
                comp = ins.next();
                if (dest == null or comp == null) {
                    std.process.fatal("Error parsing instruction: {s}\n", .{instruction});
                }
                dest_machine = dests_map.get(dest.?);
            }

            const a = get_a_bit(comp.?);
            const comp_machine = comps_map.get(comp.?);
            if (comp_machine == null or dest_machine == null or jump_machine == null) {
                std.process.fatal("Error parsing instruction: {s}\n", .{instruction});
            }

            const buf = try std.fmt.bufPrint(out_buf[bytes_out..], "111{c}{s}{s}{s}\n", .{ a, comp_machine.?, dest_machine.?, jump_machine.? });
            bytes_out += buf.len;
        }
        pc_value += 1;
    }
    const output_file = try cwd.createFile(init.io, output_path, .{ .read = false });
    defer output_file.close(init.io);
    _ = try output_file.writePositionalAll(init.io, &out_buf, 0);
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

fn hashmap_from_file(io: std.Io, allocator: std.mem.Allocator, filename: []const u8, buffer: []u8) !std.StringHashMap([]const u8) {
    const file = try std.Io.Dir.cwd().openFile(io, filename, .{ .mode = .read_only });
    defer file.close(io);

    var map = std.StringHashMap([]const u8).init(allocator);

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
