# zig-status
A simple framework for generating i3bar and swaybar compatible status bars. 

## Usage

A status bar in `zig-status` consists of two main parts, the first is the core,
a compile-time known list of `Widget`s.  These `Widget`s are each independent
display sections on the status bar, they are evaluated independently but
sequentially.  The other important part is the formatter which runs after every
`Widget` executes with mutable access to the results.

Usage as shown in `src/main.zig` is as simple as:

```zig
const std = @import("std");
const zig_status = @import("zig-status");

fn formatter(
    _: std.mem.Allocator,
    results: []zig_status.WidgetResult,
) !void {
    // Mutate every result with the style.
    for (0..results.len) |i| {
        results[i].background = "#000000B2";
        results[i].border = "#FFFFFF";
        results[i].@"align" = "center"
        results[i].separator = false;
        results[i].separator_block_width = 0;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        // Standard `zig-status` `Widget`s do not assume anything about 
        // allocated memory
        .safety = false,
    }).init;
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();

    try zig_status.run(alloc, [_]zig_status.Widget{
        try zig_status.Widgets.create_brightness(alloc),
        try zig_status.Widgets.create_battery(alloc),
        zig_status.Widgets.sysinfo,
        zig_status.Widgets.clock,
    }, formatter);
}
```
