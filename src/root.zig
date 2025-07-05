const std = @import("std");
pub const Widgets = @import("widgets/root.zig");

const UPDATE_INTERVAL_NANOSECONDS: u64 = std.time.ns_per_s;
const ARENA_RETAIN_LIMIT: usize = 1024 * 1024; // retain 1mb

const WidthInputTag = enum {
    pixels,
    string,
};

pub const WidthInput = union(WidthInputTag) {
    pixels: i32,
    string: []const u8,

    pub fn jsonStringify(self: *const WidthInput, jw: anytype) !void {
        switch (self.*) {
            .pixels => |pixels| try jw.write(pixels),
            .string => |string| try jw.write(string),
        }
    }
};

// Taken from `man swaybar-protocol(7)`
pub const WidgetResult = struct {
    // The  text  that will be displayed.
    // If  missing,  the  block  will  be
    // skipped.
    full_text: ?[]const u8,

    // If  given and the text needs to be
    // shortened due to space, this  will
    // be displayed instead of full_text
    short_text: ?[]const u8,

    // The text color to use in #RRGGBBAA
    // or #RRGGBB notation
    color: ?[]const u8,

    // The background color for the block
    // in #RRGGBBAA or #RRGGBB notation
    background: ?[]const u8,

    // The  border color for the block in
    // #RRGGBBAA or #RRGGBB notation
    border: ?[]const u8,

    // The height in pixels  of  the  top
    // border. The default is 1
    border_top: ?i32,

    // The height in pixels of the bottom
    // border. The default is 1
    border_bottom: ?i32,

    // The  width  in  pixels of the left
    // border. The default is 1
    border_left: ?i32,

    // The width in pixels of  the  right
    // border. The default is 1
    border_right: ?i32,

    // The  minimum  width to use for the
    // block. This can either be given in
    // pixels or a string can be given to
    // allow  for  it  to  be  calculated
    // based on the width of the string.
    min_width: ?WidthInput,

    // If the text does not span the full
    // width of the block, this specifies
    // how the text should be aligned in‐
    // side  of  the  block.  This can be
    // left (default), right, or center.
    @"align": ?[]const u8,

    // A name for the block. This is only
    // used to  identify  the  block  for
    // click  events.  If set, each block
    // should have a unique name and  in‐
    // stance pair.
    name: ?[]const u8,

    // The  instance  of the name for the
    // block. This is only used to  iden‐
    // tify  the  block for click events.
    // If set, each block should  have  a
    // unique name and instance pair.
    instance: ?[]const u8,

    // Whether  the  block should be dis‐
    // played as urgent. Currently  sway‐
    // bar utilizes the colors set in the
    // sway  config  for urgent workspace
    // buttons. See sway-bar(5) for  more
    // information  on bar color configu‐
    // ration.
    urgent: ?bool,

    // Whether the bar  separator  should
    // be  drawn  after  the  block.  See
    // sway-bar(5) for  more  information
    // on how to set the separator text.
    separator: ?bool,

    // The  amount  of  pixels  to  leave
    // blank after the block. The separa‐
    // tor text will  be  displayed  cen‐
    // tered  in this gap. The default is
    // 9 pixels.
    separator_block_width: ?i32,

    // The type of  markup  to  use  when
    // parsing  the  text  for the block.
    // This can either be pango  or  none
    // (default).
    markup: ?[]const u8,
};

// This function must always called `wg.finish()`
pub const WidgetFn = *const fn (
    wg: *std.Thread.WaitGroup,
    alloc: std.mem.Allocator,
    result: *WidgetResult,
) anyerror!void;

pub const FormatterFn = *const fn (
    alloc: std.mem.Allocator,
    results: []WidgetResult,
) anyerror!void;

const stdout = std.io.getStdOut().writer();

pub fn Status(comptime widget_fns: anytype) type {
    const widget_count = widget_fns_length(widget_fns);
    return comptime struct {
        const Self = @This();
        stdout: std.fs.File.Writer,
        arena: std.heap.ArenaAllocator,
        widget_results: [widget_count]WidgetResult,
        widget_fns: [widget_count]WidgetFn,
        formatter_fn: FormatterFn,

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }

        pub fn reset(self: *Self) void {
            _ = self.arena.reset(.{
                .retain_with_limit = ARENA_RETAIN_LIMIT,
            });
        }

        const Header = struct {
            version: i32, // Must be `1`

            // Whether to recieve click information to stdin
            click_events: ?bool,

            // The signal that swaybar should send to continue
            // processing
            // Defaults to `std.posix.SIG.CONT`
            cont_signal: ?i32,

            // The signal that swaybar should send to stop
            // processing
            // Defaults to `std.posix.SIG.STOP`
            stop_signal: ?i32,
        };

        pub fn render_headers(self: *Self) !void {
            const json = try std.json.stringifyAlloc(
                self.arena.allocator(),
                Header{
                    .version = 1,
                    .click_events = null,
                    .cont_signal = null,
                    .stop_signal = null,
                },
                .{
                    .emit_null_optional_fields = false,
                },
            );
            defer _ = self.arena.reset(.free_all);

            try stdout.writeAll(json);
            try stdout.writeAll("\n[");
        }

        pub fn update_results(self: *Self) !void {
            var wg: std.Thread.WaitGroup = .{};
            for (0..widget_count) |i| {
                wg.start();
                try self.widget_fns[i](
                    &wg,
                    self.arena.allocator(),
                    &self.widget_results[i],
                );
            }
            wg.wait();
        }

        pub fn render_results(self: *Self) !void {
            const resJson = try std.json.stringifyAlloc(
                self.arena.allocator(),
                self.widget_results,
                .{
                    .emit_null_optional_fields = false,
                },
            );

            try stdout.writeAll(resJson);
            try stdout.writeByte(',');
        }

        pub fn result_loop(self: *Self) !void {
            const start = try std.time.Instant.now();

            try self.update_results();
            try self.formatter_fn(
                self.arena.allocator(),
                &self.widget_results,
            );
            try self.render_results();
            self.reset();

            const end = try std.time.Instant.now();

            const since = end.since(start);
            if (since < UPDATE_INTERVAL_NANOSECONDS) {
                std.time.sleep(UPDATE_INTERVAL_NANOSECONDS - since);
            }

            try self.result_loop();
        }
    };
}

fn widget_fns_length(arr: anytype) comptime_int {
    const type_info = @typeInfo(@TypeOf(arr));
    switch (type_info) {
        .array => |array_type| {
            if (array_type.child != WidgetFn) {
                @compileError("the input array must be of WidgetFn function pointers");
            }
            return array_type.len;
        },
        else => @compileError(
            "widget_fns requires a comptime array of WidgetFn function pointers",
        ),
    }
}

pub fn create(
    alloc: std.mem.Allocator,
    // Should be an array of []WidgetFn
    comptime widget_fns: anytype,
    formatter_fn: FormatterFn,
) Status(widget_fns) {
    return .{
        .stdout = std.io.getStdOut().writer(),
        .arena = std.heap.ArenaAllocator.init(alloc),
        .widget_fns = widget_fns,
        .widget_results = std.mem.zeroes([widget_fns.len]WidgetResult),
        .formatter_fn = formatter_fn,
    };
}

pub fn run(
    alloc: std.mem.Allocator,
    // Should be an array of []WidgetFn
    comptime widget_fns: anytype,
    formatter_fn: FormatterFn,
) !void {
    var status = create(alloc, widget_fns, formatter_fn);
    try status.render_headers();
    try status.result_loop();
}

fn test_widget(wg: *std.Thread.WaitGroup, _: std.mem.Allocator, result: *WidgetResult) !void {
    result.full_text = "test";
    result.min_width = .{ .pixels = 5 };
    wg.finish();
}

fn test_formatter(_: std.mem.Allocator, results: []WidgetResult) !void {
    for (0..results.len) |i| {
        results[i].background = "#FF0000";
    }
}

test "test calling widgets" {
    var self = create(
        std.testing.allocator,
        [_]WidgetFn{
            test_widget,
            test_widget,
            test_widget,
        },
        test_formatter,
    );
    try self.render_headers();
    self.reset();
    for (self.widget_results) |res| {
        try std.testing.expectEqual(null, res.full_text);
    }
    try self.update_results();
    for (self.widget_results) |res| {
        try std.testing.expectEqual("test", res.full_text.?);
    }
    try self.formatter_fn(self.arena.allocator(), &self.widget_results);
    try self.render_results();
    self.deinit();
}
