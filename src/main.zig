const std = @import("std");
const zig_status = @import("zig-status");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .safety = false,
    }).init;
    defer _ = gpa.deinit();

    try zig_status.run(gpa.allocator(), [_]zig_status.WidgetFn{
        zig_status.Widgets.clock,
    });
}
