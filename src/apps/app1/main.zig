const std = @import("std");

export fn app_main() linksection(".text.main") callconv(.Naked) noreturn {
    while (true) {}
}
