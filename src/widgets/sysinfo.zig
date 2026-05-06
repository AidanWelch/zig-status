const std = @import("std");
const zig_status = @import("../root.zig");

fn sysinfo_fn(
    _: *std.Io.Group,
    alloc: std.mem.Allocator,
    result: *zig_status.WidgetResult,
) error{
    UnknownSystemInfo,
    OutOfMemory,
}!void {
    var info: std.os.linux.Sysinfo = undefined;
    const err = std.os.linux.errno(std.os.linux.sysinfo(&info));
    if (err != .SUCCESS) {
        return error.UnknownSystemInfo;
    }

    const total_ram = info.totalram * info.mem_unit;
    const used_ram = (info.totalram - info.freeram) * info.mem_unit;

    result.full_text = try std.fmt.allocPrint(
        alloc,
        "RAM: {Bi:.2} / {Bi:.2}",
        .{ used_ram, total_ram },
    );

    result.min_width = .{ .string = "RAM: XXXX.XXUUU / XXXX.XXUUU" };
}

pub const sysinfo = zig_status.fnToWidget(sysinfo_fn);
