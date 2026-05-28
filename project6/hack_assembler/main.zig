const std = @import("std");
const expect = std.testing.expect;

const INPUT_FILE = "Add.asm";
const DESTS_FILE = "dests.txt";
const COMPS_FILE = "comps.txt";
const BUFFER_SIZE = 1024;

pub fn main() !void {
    var comps_buf = [_]u8{0} ** BUFFER_SIZE;
    var dests_buf = [_]u8{0} ** BUFFER_SIZE;

    var comps_map = try hashmap_from_file(COMPS_FILE, &comps_buf);
    var dests_map = try hashmap_from_file(DESTS_FILE, &dests_buf);

    const file = try std.fs.cwd().openFile(INPUT_FILE, .{ .mode = .read_only });
    defer file.close();

    var read_buffer = [_]u8{0} ** BUFFER_SIZE;

    const bytes_read = try file.read(&read_buffer);
    var instructions = std.mem.splitScalar(u8, read_buffer[0 .. bytes_read - 1], '\n');

    var buf = [_]u8{0} ** 16;
    while (instructions.next()) |instruction| {
        if (std.mem.startsWith(u8, instruction, "//")) {
            continue;
        }

        if (instruction.len == 0) {
            continue;
        }

        std.debug.print("---------------------\n", .{});
        if (std.mem.startsWith(u8, instruction, "@")) {
            const value = instruction[1..instruction.len];
            const num_value = try std.fmt.parseInt(u16, value, 10);
            _ = try std.fmt.bufPrint(&buf, "{b:0>16}", .{num_value});
            std.debug.print("A-instruction symbol:\t@{s}\n", .{value});
            std.debug.print("A-instruction machine:\t{s}\n", .{buf});
        } else {
            var dest_comp = std.mem.splitScalar(u8, instruction, '=');

            const dest = dest_comp.next() orelse unreachable;
            const comp = dest_comp.next() orelse unreachable;

            const a = get_a_bit(comp);
            const dest_machine = dests_map.get(dest) orelse unreachable;
            const comp_machine = comps_map.get(comp) orelse unreachable;
            const jump_machine = "000"; // No jump for now

            _ = try std.fmt.bufPrint(&buf, "111{c}{s}{s}{s}", .{ a, comp_machine, dest_machine, jump_machine });
            std.debug.print("C-instruction symbol:\t{s}={s}\n", .{ dest, comp });
            std.debug.print("C-instruction machine:\t{s}\n", .{buf});
        }
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

fn hashmap_from_file(filename: []const u8, buffer: []u8) !std.StringHashMap([]const u8) {
    const file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer file.close();

    var map = std.StringHashMap([]const u8).init(std.heap.page_allocator);
    {
        const bytes_read = try file.read(buffer);
        var lines = std.mem.splitScalar(u8, buffer[0 .. bytes_read - 1], '\n');

        while (lines.next()) |line| {
            var key_val = std.mem.splitScalar(u8, line, ':');
            const symbol = key_val.next() orelse unreachable;
            const machine = key_val.next() orelse unreachable;
            _ = try map.put(symbol, machine);
        }
    }

    return map;
}
