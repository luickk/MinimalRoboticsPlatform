const std = @import("std");
const arm = @import("arm");
const ProccessorRegMap = arm.processor.ProccessorRegMap;
const CpuContext = arm.cpuContext.CpuContext;
const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;
const board = @import("board");
const sysCalls = @import("sysCalls.zig");
const bcm2835IntHandle = @import("board/raspi3b/bcm2835IntHandle.zig");
const gic = arm.gicv2;
const gt = arm.genericTimer;

pub fn irqHandler(temp_context: *CpuContext, tmp_int_type: usize) callconv(.C) void {
    var int_type = tmp_int_type;

    // copy away from stack top
    var context = temp_context.*;
    context.int_type = int_type;

    var int_type_en = std.meta.intToEnum(gic.ExceptionType, int_type) catch {
        printContext(&context);
        return;
    };

    switch (int_type_en) {
        .el0Sync => {
            var ec = @truncate(u6, context.esr_el1 >> 26);
            var ec_en = std.meta.intToEnum(ProccessorRegMap.Esr_el1.ExceptionClass, ec) catch {
                kprint("Error decoding ExceptionClass 0x{x} \n", .{ec});
                printContext(&context);
                return;
            };
            if (ec_en == .svcInstExAArch64) {
                sysCalls.sysCallPrint(&context);
            } else {
                kprint("- el0 sync exception \n", .{});
                printContext(&context);
            }
        },
        // timer interrupts with custom timers per voard
        .el1Irq, .el0Irq => {
            if (board.config.board == .raspi3b)
                bcm2835IntHandle.irqHandler(&context);
            if (board.config.board == .qemuVirt)
                gt.timerInt(&context);
        },
        else => {
            // printing debug information
            var iss = @truncate(u25, context.esr_el1);
            var ifsc = @truncate(u6, context.esr_el1);
            var il = @truncate(u1, context.esr_el1 >> 25);
            var ec = @truncate(u6, context.esr_el1 >> 26);
            var iss2 = @truncate(u5, context.esr_el1 >> 32);
            _ = iss;
            _ = iss2;

            kprint(".........sync exc............\n", .{});
            kprint("Int Type: {s} \n", .{@tagName(int_type_en)});
            var ec_en = std.meta.intToEnum(ProccessorRegMap.Esr_el1.ExceptionClass, ec) catch {
                kprint("Error decoding ExceptionClass 0x{x} \n", .{ec});
                printContext(&context);
                return;
            };
            var ifsc_en = std.meta.intToEnum(ProccessorRegMap.Esr_el1.Ifsc, ifsc) catch {
                kprint("Error decoding ExceptionClass IFSC 0x{x} \n", .{ifsc});
                printContext(&context);
                return;
            };
            kprint("Exception Class(from esp reg): {s} \n", .{@tagName(ec_en)});
            kprint("IFC(from esp reg): {s} \n", .{@tagName(ifsc_en)});
            kprint("- debug info: \n", .{});
            printContext(&context);

            if (il == 1) {
                kprint("32 bit instruction trapped \n", .{});
            } else {
                kprint("16 bit instruction trapped \n", .{});
            }
            kprint(".........sync exc............\n", .{});
            if (ec_en == ProccessorRegMap.Esr_el1.ExceptionClass.bkptInstExecAarch64) {
                kprint("[kernel] halting execution due to debug trap\n", .{});
                while (true) {}
            }
        },
    }
}
pub fn irqElxSpx(temp_context: *CpuContext, tmp_int_type: usize) callconv(.C) void {
    irqHandler(temp_context, tmp_int_type);
}

fn printContext(context: *CpuContext) void {
    kprint("el: {d} \n", .{context.el});
    kprint("esr_el1: 0x{x} \n", .{context.esr_el1});
    kprint("far_el1: 0x{x} \n", .{context.far_el1});
    kprint("elr_el1: 0x{x} \n", .{context.elr_el1});
    kprint("- sys regs: \n", .{});
    kprint("sp: 0x{x} \n", .{context.sp});
    kprint("spSel: {d} \n", .{context.sp_sel});
    kprint("pc: 0x{x} \n", .{context.pc});
    kprint("lr(x30): 0x{x} \n", .{context.x30});
    kprint("x0: 0x{x}, x1: 0x{x}, x2: 0x{x}, x3: 0x{x}, x4: 0x{x} \n", .{ context.x0, context.x1, context.x2, context.x3, context.x4 });
    kprint("x5: 0x{x}, x6: 0x{x}, x7: 0x{x}, x8: 0x{x}, x9: 0x{x} \n", .{ context.x5, context.x6, context.x7, context.x8, context.x9 });
    kprint("x10: 0x{x}, x11: 0x{x}, x12: 0x{x}, x13: 0x{x}, x14: 0x{x} \n", .{ context.x10, context.x11, context.x12, context.x13, context.x14 });
    kprint("x15: 0x{x}, x16: 0x{x}, x17: 0x{x}, x18: 0x{x}, x19: 0x{x} \n", .{ context.x15, context.x16, context.x17, context.x18, context.x19 });
    kprint("x20: 0x{x}, x21: 0x{x}, x22: 0x{x}, x23: 0x{x}, x24: 0x{x} \n", .{ context.x20, context.x21, context.x22, context.x23, context.x24 });
    kprint("x25: 0x{x}, x26: 0x{x}, x27: 0x{x}, x28: 0x{x}, x29: 0x{x} \n", .{ context.x25, context.x26, context.x27, context.x28, context.x29 });
}
