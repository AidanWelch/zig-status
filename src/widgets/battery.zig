const std = @import("std");
const zig_status = @import("../root.zig");

// Largely inspired by
// https://github.com/fastfetch-cli/fastfetch/blob/dev/src/detection/battery/battery_linux.c

const Battery = struct {
    allocator: std.mem.Allocator,
    ps_dir: std.fs.Dir,

    pub fn update_result(
        self: *Battery,
        wg: *std.Thread.WaitGroup,
        alloc: std.mem.Allocator,
        result: *zig_status.WidgetResult,
    ) !void {
        defer wg.finish();
        result.min_width = .{ .string = " X 100% " };
        var capacity_buffer: [3]u8 = undefined;
        var capacity = try self.ps_dir.readFile("capacity", &capacity_buffer);
        if (capacity.len > 0 and capacity[capacity.len - 1] == '\n') {
            capacity.len -= 1;
        }
        var buffer: [64]u8 = undefined;

        const status = try self.ps_dir.readFile("status", &buffer);
        if (status.len < 11 or
            !std.mem.eql(u8, "Discharging", status[0..11]))
        {
            result.full_text = try std.fmt.allocPrint(
                alloc,
                "⚡︎ {s}%",
                .{ capacity }
            );
            return;
        }

        result.full_text = try std.fmt.allocPrint(
            alloc,
            "{s}%",
            .{ capacity },
        );
    }

    pub fn deinit(self: *Battery) void {
        self.ps_dir.close();
        self.allocator.destroy(self);
    }
};

fn isBatteryDir(dir: std.fs.Dir) !bool {
    var buffer: [64]u8 = undefined;
    const ps_type = try dir.readFile("type", &buffer);
    if (ps_type.len < 7 or !std.mem.eql(u8, "Battery", ps_type[0..7])) {
        return false;
    }
    const scope = dir.readFile("scope", &buffer) catch "other";
    if (scope.len >= 6 and std.mem.eql(u8, "Device", scope[0..6])) {
        return false;
    }
    const capacity = try dir.readFile("capacity", &buffer);
    if (capacity.len == 0) {
        return false;
    }
    const status = try dir.readFile("status", &buffer);
    if (status.len == 0) {
        return false;
    }
    const charge_now = try dir.readFile("charge_now", &buffer);
    if (charge_now.len == 0) {
        return false;
    }
    const current_now = try dir.readFile("current_now", &buffer);
    if (current_now.len == 0) {
        return false;
    }
    return true;
}

fn getBatteryDir() !std.fs.Dir {
    var power_supply_dir = try std.fs.openDirAbsolute("/sys/class/power_supply/", .{
        .access_sub_paths = true,
        .iterate = true,
    });
    defer power_supply_dir.close();

    var power_supply_iter = power_supply_dir.iterateAssumeFirstIteration();
    while (try power_supply_iter.next()) |ps_entry| {
        if (ps_entry.name[0] == '.' or ps_entry.kind != .sym_link) {
            continue;
        }

        var ps_dir = try power_supply_dir.openDir(
            ps_entry.name,
            .{ .access_sub_paths = true },
        );
        errdefer ps_dir.close();

        if (try isBatteryDir(ps_dir)) {
            return ps_dir;
        }
        ps_dir.close();
    }
    return error.NoBatteryFound;
}

pub fn create_battery(alloc: std.mem.Allocator) !zig_status.Widget {
    var bat = try alloc.create(Battery);
    errdefer alloc.destroy(bat);
    bat.ps_dir = try getBatteryDir();
    bat.allocator = alloc;
    return zig_status.ptrToWidget(bat);
}
