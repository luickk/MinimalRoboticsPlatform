const std = @import("std");
const arm = @import("arm");
const ProccessorRegMap = arm.processor.ProccessorRegMap;
const CpuContext = arm.cpuContext.CpuContext;
const k_utils = @import("utils.zig");
const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;
const board = @import("board");
const sysCalls = @import("sysCalls.zig");
// const bcm2835IntHandle = @import("board/raspi3b/bcm2835IntHandle.zig");
const gic = arm.gicv2;
const gt = arm.genericTimer;

pub fn trapHandler(on_stack_context: *CpuContext, tmp_int_type: usize) callconv(.C) void {
    var int_type = tmp_int_type; // copy away from stack top (unsure about C abi standards...)
    var context = on_stack_context.*;
    // kprint("unique \n", .{});
    context.int_type = int_type;
    // kprint("cpucontext size: {d} \n", .{@sizeOf(CpuContext)});
    // kprint("context: {any} \n", .{context});
    // kprint("pc: {x} \n", .{ProccessorRegMap.getCurrentPc()});
    var int_type_en = std.meta.intToEnum(gic.ExceptionType, int_type) catch {
        printExc(&context, null);
        return;
    };

    switch (int_type_en) {
        .el0Sync, .el1Sync => {
            var ec = @truncate(u6, context.esr_el1 >> 26);
            var ec_en = std.meta.intToEnum(ProccessorRegMap.Esr_el1.ExceptionClass, ec) catch {
                kprint("Error decoding ExceptionClass 0x{x} \n", .{ec});
                printExc(&context, int_type_en);
                return;
            };
            switch (ec_en) {
                .svcInstExAArch64 => {
                    var sys_call_found: bool = false;
                    for (sysCalls.sysCallTable) |*sys_call| {
                        if (sys_call.id == context.x8) {
                            sys_call.fn_call(on_stack_context);
                            sys_call_found = true;
                        }
                    }
                    if (!sys_call_found) {
                        kprint("[kernel] SysCall id NOT found! \n", .{});
                        printExc(&context, int_type_en);
                    }
                },
                .bkptInstExecAarch64 => {
                    kprint("[app] halting execution due to debug trap\n", .{});
                    printContext(&context);
                    kprint("pc: 0x{x}\n", .{ProccessorRegMap.getCurrentPc()});
                    haltExec(true, on_stack_context);
                },
                else => {
                    printExc(&context, int_type_en);
                },
            }
        },
        // timer interrupts with custom timers per board
        .el1Irq, .el0Irq => {
            if (board.driver.secondaryInterruptConrtollerDriver) |secondary_ic| {
                if (secondary_ic.context.handler_fn) |handler| handler(&context);
            }
            
            if (std.mem.eql(u8, board.driver.timerDriver.timer_name, "arm_gt")) {
                board.driver.timerDriver.timerTick(&context) catch |e| {
                    kprint("kernel timer error {s} \n", .{@errorName(e)});
                    return;
                };
            }
        },
        else => {
            printExc(&context, int_type_en);
        },
    }
}

fn printExc(context: *CpuContext, int_type_en: ?gic.ExceptionType) void {
    // printing debug information
    var iss = @truncate(u25, context.esr_el1);
    var ifsc = @truncate(u6, context.esr_el1);
    var il = @truncate(u1, context.esr_el1 >> 25);
    var ec = @truncate(u6, context.esr_el1 >> 26);
    var iss2 = @truncate(u5, context.esr_el1 >> 32);
    _ = iss;
    _ = iss2;

    kprint(".........sync exc............\n", .{});
    if (int_type_en) |int_type| kprint("Int Type: {s} \n", .{@tagName(int_type)});
    var ec_en = std.meta.intToEnum(ProccessorRegMap.Esr_el1.ExceptionClass, ec) catch {
        kprint("Error decoding ExceptionClass 0x{x} \n", .{ec});
        printContext(context);
        return;
    };
    var ifsc_en = std.meta.intToEnum(ProccessorRegMap.Esr_el1.Ifsc, ifsc) catch {
        kprint("Error decoding ExceptionClass IFSC 0x{x} \n", .{ifsc});
        printContext(context);
        return;
    };
    kprint("Exception Class(from esp reg): {s} \n", .{@tagName(ec_en)});
    kprint("IFC(from esp reg): {s} \n", .{@tagName(ifsc_en)});
    kprint("- debug info: \n", .{});
    printContext(context);
    kprint(".........sync exc............\n", .{});
    if (il == 1) {
        kprint("32 bit instruction trapped \n", .{});
    } else {
        kprint("16 bit instruction trapped \n", .{});
    }
    kprint(".........sync exc............\n", .{});
}

fn printContext(context: *CpuContext) void {
    kprint("--------- context --------- \n", .{});
    kprint("irq el: {d} \n", .{context.el});
    kprint("far_el1: 0x{x} \n", .{context.far_el1});
    kprint("irq esr_el1: 0x{x} \n", .{context.esr_el1});
    kprint("irq elr_el1: 0x{x} \n", .{context.elr_el1});
    kprint("- sys regs: \n", .{});
    kprint("sp_el0: 0x{x} \n", .{context.sp_el0});
    kprint("lr(x30): 0x{x} \n", .{context.x30});
    kprint("irq sp_el1: 0x{x} \n", .{context.sp_el1});
    kprint("irq spSel: {d} \n", .{context.sp_sel});
    kprint("x0: 0x{x}, x1: 0x{x}, x2: 0x{x}, x3: 0x{x}, x4: 0x{x} \n", .{ context.x0, context.x1, context.x2, context.x3, context.x4 });
    kprint("x5: 0x{x}, x6: 0x{x}, x7: 0x{x}, x8: 0x{x}, x9: 0x{x} \n", .{ context.x5, context.x6, context.x7, context.x8, context.x9 });
    kprint("x10: 0x{x}, x11: 0x{x}, x12: 0x{x}, x13: 0x{x}, x14: 0x{x} \n", .{ context.x10, context.x11, context.x12, context.x13, context.x14 });
    kprint("x15: 0x{x}, x16: 0x{x}, x17: 0x{x}, x18: 0x{x}, x19: 0x{x} \n", .{ context.x15, context.x16, context.x17, context.x18, context.x19 });
    kprint("x20: 0x{x}, x21: 0x{x}, x22: 0x{x}, x23: 0x{x}, x24: 0x{x} \n", .{ context.x20, context.x21, context.x22, context.x23, context.x24 });
    kprint("x25: 0x{x}, x26: 0x{x}, x27: 0x{x}, x28: 0x{x}, x29: 0x{x} \n", .{ context.x25, context.x26, context.x27, context.x28, context.x29 });
    kprint("--------- context --------- \n", .{});
}

fn haltExec(halt_execution: bool, on_stack_context: *CpuContext) void {
    if (!halt_execution) {
        on_stack_context.elr_el1 += 4;
    } else {
        while (true) {}
    }
}
