const std = @import("std");
const zig_status = @import("zig-status");

fn formatter(
    _: std.mem.Allocator,
    results: []zig_status.WidgetResult,
) !void {
    for (0..results.len) |i| {
        results[i].background = "#000000B2";
        results[i].border = "#FFFFFF";
        results[i].@"align" = "center";
        results[i].separator = false;
        results[i].separator_block_width = 0;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .safety = false,
    }).init;
    defer _ = gpa.deinit();

    try zig_status.run(gpa.allocator(), [_]zig_status.WidgetFn{
        zig_status.Widgets.sysinfo,
        zig_status.Widgets.clock,
    }, formatter);
}
