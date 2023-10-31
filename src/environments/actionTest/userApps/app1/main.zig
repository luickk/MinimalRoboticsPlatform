const std = @import("std");
const appLib = @import("appLib");
const board = @import("board");
const arm = @import("arm");
const cpuContext = arm.cpuContext;
const AppAlloc = appLib.AppAllocator;
const sysCalls = appLib.sysCalls;
const kprint = appLib.sysCalls.SysCallPrint.kprint;

var test_counter: usize = 0;

export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    kprint("app1 initial pid: {d} \n", .{pid});
    var read_state: bool = true;
    sysCalls.updateStatus("groundContact", true) catch |e| {
        kprint("sysCalls updateStatus err: {s} \n", .{@errorName(e)});
    };
    while (true) {
        read_state = sysCalls.readStatus(bool, "groundContact") catch |e| {
            kprint("sysCalls readStatus err: {s} \n", .{@errorName(e)});
            while (true) {}
        };
        kprint("status read 1: {any} \n", .{read_state});
        if (read_state) {
            sysCalls.updateStatus("groundContact", false) catch |e| {
                kprint("sysCalls updateStatus err: {s} \n", .{@errorName(e)});
            };
            kprint("status set 1 to false \n", .{});
        }
    }
}

// var test_counter: usize = 0;
// export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
//     kprint("app1 initial pid: {d} \n", .{pid});
//     while (true) {
//         test_counter += 1;

//         sysCalls.updateStatus("height", @intCast(isize, test_counter)) catch |e| {
//             kprint("sysCalls updateStatus err: {s} \n", .{@errorName(e)});
//         };
//         var read = sysCalls.readStatus(isize, "height") catch |e| {
//             kprint("sysCalls readStatus err: {s} \n", .{@errorName(e)});
//             while (true) {}
//         };
//         kprint("status read: {d} \n", .{read});
//     }
// }
