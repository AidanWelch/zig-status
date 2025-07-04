const std = @import("std");
const zig_status = @import("../root.zig");

pub fn clock(
    wg: *std.Thread.WaitGroup,
    alloc: std.mem.Allocator,
    result: *zig_status.WidgetResult,
) !void {
    const now: u64 = @intCast(std.time.timestamp());
    const text = try std.fmt.allocPrint(alloc, "{d}", .{now});
    result.full_text = text;
    wg.finish();
}
