const std = @import("std");
const zig_status = @import("../root.zig");

// Largely inspired by
// https://github.com/fastfetch-cli/fastfetch/blob/dev/src/detection/battery/battery_linux.c

fn getBatteryDir() !std.fs.Dir {
    const power_supply_dir = try std.fs.openDirAbsolute("/sys/class/power_supply/", .{
        .access_sub_paths = true,
        .iterate = true,
    });
    defer power_supply_dir.close();
    const power_supply_iter = power_supply_dir.iterateAssumeFirstIteration();

    while (try power_supply_iter.next()) |pw| {
        if (pw.name[0] == '.' or pw.kind != .directory) {
            continue;
        }
    }
}

const Battery = struct {
    allocator: std.mem.Allocator,
    call_count: u64,

    pub fn update_result(
        self: *Battery,
        wg: *std.Thread.WaitGroup,
        alloc: std.mem.Allocator,
        result: *zig_status.WidgetResult,
    ) error{
        OutOfMemory,
    }!void {
        self.call_count += 1;
        result.full_text = try std.fmt.allocPrint(
            alloc,
            "Called: {}",
            .{self.call_count},
        );
        result.min_width = .{ .string = "Called: 999999999999999999999999999" };

        wg.finish();
    }

    pub fn deinit(self: *Battery) void {
        self.allocator.destroy(self);
    }
};

pub fn create_battery(alloc: std.mem.Allocator) !zig_status.Widget {
    var bat = try alloc.create(Battery);
    bat.call_count = 0;
    bat.allocator = alloc;
    return zig_status.ptrToWidget(bat);
}
