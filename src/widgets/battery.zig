const std = @import("std");
const zig_status = @import("../root.zig");

// Largely inspired by
// https://github.com/fastfetch-cli/fastfetch/blob/dev/src/detection/battery/battery_linux.c

const Battery = struct {
    allocator: std.mem.Allocator,
    ps_dir: std.Io.Dir,
    threaded: std.Io.Threaded,

    pub fn update_result(
        self: *Battery,
        _: *std.Io.Group,
        alloc: std.mem.Allocator,
        result: *zig_status.WidgetResult,
    ) !void {
        const io = self.threaded.io();
        result.min_width = .{ .string = " X 100% " };
        var capacity_buffer: [3]u8 = undefined;
        var capacity = try self.ps_dir.readFile(io, "capacity", &capacity_buffer);
        if (capacity.len > 0 and capacity[capacity.len - 1] == '\n') {
            capacity.len -= 1;
        }
        var buffer: [64]u8 = undefined;

        const status = try self.ps_dir.readFile(io, "status", &buffer);
        if (status.len < 11 or
            !std.mem.eql(u8, "Discharging", status[0..11]))
        {
            result.full_text = try std.fmt.allocPrint(alloc, "⚡︎ {s}%", .{capacity});
            return;
        }

        result.full_text = try std.fmt.allocPrint(
            alloc,
            "{s}%",
            .{capacity},
        );
    }

    pub fn deinit(self: *Battery) void {
        self.ps_dir.close(self.threaded.io());
        self.threaded.deinit();
        self.allocator.destroy(self);
    }
};

fn isBatteryDir(io: std.Io, dir: std.Io.Dir) !bool {
    var buffer: [64]u8 = undefined;
    const ps_type = try dir.readFile(io, "type", &buffer);
    if (ps_type.len < 7 or !std.mem.eql(u8, "Battery", ps_type[0..7])) {
        return false;
    }
    const scope = dir.readFile(io, "scope", &buffer) catch "other";
    if (scope.len >= 6 and std.mem.eql(u8, "Device", scope[0..6])) {
        return false;
    }
    const capacity = try dir.readFile(io, "capacity", &buffer);
    if (capacity.len == 0) {
        return false;
    }
    const status = try dir.readFile(io, "status", &buffer);
    if (status.len == 0) {
        return false;
    }
    return true;
}

fn getBatteryDir(io: std.Io) !std.Io.Dir {
    var power_supply_dir = try std.Io.Dir.openDirAbsolute(
        io, 
        "/sys/class/power_supply/", .{
            .access_sub_paths = true,
            .iterate = true,
        }
    );
    defer power_supply_dir.close(io);

    var power_supply_iter = power_supply_dir.iterateAssumeFirstIteration();
    while (try power_supply_iter.next(io)) |ps_entry| {
        if (ps_entry.name[0] == '.' or ps_entry.kind != .sym_link) {
            continue;
        }

        var ps_dir = try power_supply_dir.openDir(
            io,
            ps_entry.name,
            .{ .access_sub_paths = true },
        );
        errdefer ps_dir.close(io);

        if (isBatteryDir(io, ps_dir) catch false) {
            return ps_dir;
        }
        ps_dir.close(io);
    }
    return error.NoBatteryFound;
}

pub fn create_battery(alloc: std.mem.Allocator) !zig_status.Widget {
    var bat = try alloc.create(Battery);
    errdefer alloc.destroy(bat);
    bat.threaded = std.Io.Threaded.init(alloc, .{});
    bat.ps_dir = try getBatteryDir(bat.threaded.io());
    bat.allocator = alloc;
    return zig_status.ptrToWidget(bat);
}
