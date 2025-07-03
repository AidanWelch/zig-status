const std = @import("std");

const UPDATE_INTERVAL_NANOSECONDS: u64 = std.time.ns_per_s;

pub const WidgetResult = struct {
    full_text: []const u8,
};

pub const WidgetFn = *const fn (
    wg: *std.Thread.WaitGroup,
    result: *WidgetResult,
) void;

pub fn Status(comptime widget_fns: anytype) type {
    const widget_count = widget_fns_length(widget_fns);
    return comptime struct {
        const Self = @This();
        stdout: std.fs.File.Writer,
        arena: std.heap.ArenaAllocator,
        widget_results: [widget_count]WidgetResult,
        widget_fns: [widget_count]WidgetFn,

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }

        fn write_error(self: *Self, comptime error_msg: []const u8) void {
            for (0..widget_count) |i| {
                self.widget_results[i].full_text = error_msg;
            }
        }

        pub fn update_results(self: *Self) void {
            var wg: std.Thread.WaitGroup = .{};
            for (0..widget_count) |i| {
                wg.start();
                self.widget_fns[i](&wg, &self.widget_results[i]);
            }
            wg.wait();
        }

        pub fn result_loop(self: *Self) void {
            const start = std.time.Instant.now()
                catch return self.write_error("clock error at fetch start");
            
            self.update_results();

            const end = std.time.Instant.now() 
                catch return self.write_error("clocke error at fetch end");
            
            const since = end.since(start);
            if (since < UPDATE_INTERVAL_NANOSECONDS) {
                std.time.sleep(UPDATE_INTERVAL_NANOSECONDS - since);
            }

            self.result_loop();
        }
    };
}

fn widget_fns_length(arr: anytype) comptime_int {
    const error_msg = 
        "widget_fns requires a comptime array of WidgetFn function pointers"; 
    const type_info = @typeInfo(@TypeOf(arr));
    switch (type_info) {
        .array => |array_type| {
           if (array_type.child != WidgetFn) {
               @compileError(error_msg);
            }
           return array_type.len;
        },
        else => @compileError(error_msg),
    }
}

pub fn create(
    alloc: std.mem.Allocator, 
    // Should be an array of []WidgetFn
    comptime widget_fns: anytype,
) Status(widget_fns) {
    return .{
        .stdout = std.io.getStdOut().writer(),
        .arena = std.heap.ArenaAllocator.init(alloc),
        .widget_fns = widget_fns,
        .widget_results = undefined, 
    };
}


pub fn run(
    alloc: std.mem.Allocator, 
    // Should be an array of []WidgetFn
    comptime widget_fns: anytype,
) void {
    var status = create(alloc, widget_fns);
    status.result_loop();
}

fn test_widget (wg: *std.Thread.WaitGroup, result: *WidgetResult) void {
    result.full_text = "test";
    wg.finish();
}

test "test calling widgets" {
    var self = create(
        std.testing.allocator,
        [_]WidgetFn { 
            test_widget,
            test_widget,
            test_widget,
        },
    );
    for (self.widget_results) |res| {
        try std.testing.expect(
            !std.mem.eql(u8, "test", res.full_text)
        );
    }
    self.update_results();
    for (self.widget_results) |res| {
        try std.testing.expectEqual("test", res.full_text);
    }
}
