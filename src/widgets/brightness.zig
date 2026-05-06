const std = @import("std");
const zig_status = @import("../root.zig");

const Backlight = struct {
    allocator: std.mem.Allocator,
    bl_dir: std.Io.Dir,
    threaded: std.Io.Threaded,

    pub fn update_result(
        self: *Backlight,
        _: *std.Io.Group,
        alloc: std.mem.Allocator,
        result: *zig_status.WidgetResult,
    ) !void {
        const io = self.threaded.io();
        result.min_width = .{ .string = " X 100% " };
        var brightness_buffer: [32]u8 = undefined;
        var brightness_str = try self.bl_dir.readFile(io, "brightness", &brightness_buffer);
        // From what I can tell its not guaranteed that the file ends with a new line
        if (brightness_str.len > 0 and brightness_str[brightness_str.len - 1] == '\n') {
            brightness_str.len -= 1;
        }
        const brightness = try std.fmt.parseFloat(f64, brightness_str);

        var max_brightness_buffer: [32]u8 = undefined;
        var max_brightness_str = try self.bl_dir.readFile(io, "max_brightness", &max_brightness_buffer);
        if (max_brightness_str.len > 0 and max_brightness_str[max_brightness_str.len - 1] == '\n') {
            max_brightness_str.len -= 1;
        }
        const max_brightness = try std.fmt.parseFloat(f64, max_brightness_str);

        result.full_text = try std.fmt.allocPrint(
            alloc,
            "🔆 {d:.0}%",
            .{(brightness / max_brightness) * 100},
        );
    }

    pub fn deinit(self: *Backlight) void {
        self.bl_dir.close(self.threaded.io());
        self.threaded.deinit();
        self.allocator.destroy(self);
    }
};

const FB_BLANK_UNBLANK = '0';
fn isBacklightDir(io: std.Io, dir: std.Io.Dir) !bool {
    var buffer: [64]u8 = undefined;

    const bl_power = try dir.readFile(io, "bl_power", &buffer);
    if (bl_power.len == 0 or bl_power[0] != FB_BLANK_UNBLANK) {
        return false;
    }
    const brightness = try dir.readFile(io, "brightness", &buffer);
    if (brightness.len == 0) {
        return false;
    }
    const max_brightness = try dir.readFile(io, "max_brightness", &buffer);
    if (max_brightness.len == 0) {
        return false;
    }
    return true;
}

fn getBacklightDir(io: std.Io) !std.Io.Dir {
    var backlight_dir = try std.Io.Dir.openDirAbsolute(io, 
        "/sys/class/backlight/", .{
            .access_sub_paths = true,
            .iterate = true,
        }
    );
    defer backlight_dir.close(io);

    var backlight_iter = backlight_dir.iterateAssumeFirstIteration();
    while (try backlight_iter.next(io)) |bl_entry| {
        if (bl_entry.name[0] == '.' or bl_entry.kind != .sym_link) {
            continue;
        }

        var bl_dir = try backlight_dir.openDir(
            io,
            bl_entry.name,
            .{ .access_sub_paths = true },
        );
        errdefer bl_dir.close(io);

        if (try isBacklightDir(io, bl_dir)) {
            return bl_dir;
        }
        bl_dir.close(io);
    }
    return error.NoBacklightFound;
}

pub fn create_brightness(alloc: std.mem.Allocator) !zig_status.Widget {
    var bl = try alloc.create(Backlight);
    errdefer alloc.destroy(bl);
    bl.allocator = alloc;
    bl.threaded = std.Io.Threaded.init(alloc, .{});
    bl.bl_dir = try getBacklightDir(bl.threaded.io());
    return zig_status.ptrToWidget(bl);
}
