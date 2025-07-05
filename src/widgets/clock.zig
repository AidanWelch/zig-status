const std = @import("std");
const zig_status = @import("../root.zig");
const time = @cImport({
    @cDefine("_FILE_OFFSET_BITS", "64");
    @cDefine("_TIME_BITS", "64");
    @cInclude("time.h");
});

// See man strftime(3)
var FORMATTING_STRING: [:0]const u8 = "%D %T";
const OUTPUT_BUFFER_LENGTH = 18; // Calculate this based on the formatting
// string or just choose a number that
// comfortable accomodate the output.
// Since the output is formatted using a c
// functions the output is a c-string, which
// is NULL terminated, so you need to add 1
// additional byte for that NULL byte

pub fn clock(
    wg: *std.Thread.WaitGroup,
    alloc: std.mem.Allocator,
    result: *zig_status.WidgetResult,
) error{
    FailedToGetTime,
    FailedToConvertToLocalTime,
    OutputBufferShorterThanNeededLength,
    OutOfMemory,
}!void {
    const now = time.time(null);
    if (now == -1) {
        return error.FailedToGetTime;
    }

    var local: time.struct_tm = std.mem.zeroes(time.struct_tm);
    if (time.localtime_r(&now, &local) == null) {
        return error.FailedToConvertToLocalTime;
    }

    // Format the time into `MM/DD/YYYY hh:mm:ss`, can't use
    // `std.fmt.allocPrint` because it adds a leading `+`
    var text = try alloc.alloc(u8, OUTPUT_BUFFER_LENGTH);
    const text_len = time.strftime(
        text.ptr,
        OUTPUT_BUFFER_LENGTH,
        FORMATTING_STRING.ptr,
        &local,
    );
    if (text_len == 0) {
        return error.OutputBufferShorterThanNeededLength;
    }

    result.full_text = text[0..text_len];
    wg.finish();
}
