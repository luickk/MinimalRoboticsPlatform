const std = @import("std");
const arm = @import("arm");

pub fn ceilRoundToMultiple(inp: usize, multiple: usize) !usize {
    return inp + (multiple - (try std.math.mod(usize, inp, multiple)));
}

pub fn assert(ok: bool) void {
    if (!ok) unreachable; // assertion failure
}
