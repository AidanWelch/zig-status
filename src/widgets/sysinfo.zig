const std = @import("std");
const zig_status = @import("../root.zig");

// Must be in increasing order
const UNITS = [_][]const u8{
    "B",   "KiB", "MiB", "GiB", "TiB",
    "PiB", "EiB", "ZiB", "YiB",
};

const Memory = struct {
    size: u64,
    pub fn format(
        self: Memory,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const fsize: f64 = @floatFromInt(self.size);

        var unit = UNITS[0];
        var val = fsize;
        for (UNITS, 0..) |u, i| {
            const unit_val = std.math.pow(u64, 1024, i);
            if (self.size / unit_val == 0) {
                break;
            }
            unit = u;
            val = fsize / @as(f64, @floatFromInt(unit_val));
        }

        try writer.print("{d:.2} {s}", .{ val, unit });
    }
};

pub fn sysinfo(
    wg: *std.Thread.WaitGroup,
    alloc: std.mem.Allocator,
    result: *zig_status.WidgetResult,
) error{
    UnknownSystemInfo,
    OutOfMemory,
}!void {
    var info: std.os.linux.Sysinfo = undefined;
    if (std.os.linux.E.init(
        std.os.linux.sysinfo(&info),
    ) != .SUCCESS) {
        return error.UnknownSystemInfo;
    }

    const total_ram = Memory{
        .size = info.totalram * info.mem_unit,
    };
    const used_ram = Memory{
        .size = (info.totalram - info.freeram) * info.mem_unit,
    };

    result.full_text = try std.fmt.allocPrint(
        alloc,
        "RAM: {} / {}",
        .{ used_ram, total_ram },
    );
    wg.finish();
}
