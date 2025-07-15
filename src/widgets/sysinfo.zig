const std = @import("std");
const zig_status = @import("../root.zig");

fn sysinfo_fn(
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

    const total_ram = std.fmt.fmtIntSizeBin(
        info.totalram * info.mem_unit,
    );
    const used_ram = std.fmt.fmtIntSizeBin(
        (info.totalram - info.freeram) * info.mem_unit,
    );

    result.full_text = try std.fmt.allocPrint(
        alloc,
        "RAM: {:.2} / {:.2}",
        .{ used_ram, total_ram },
    );

    result.min_width = .{ .string = "RAM: XXXX.XXUUU / XXXX.XXUUU" };

    wg.finish();
}

pub const sysinfo = zig_status.fnToWidget(sysinfo_fn);
