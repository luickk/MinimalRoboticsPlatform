const kprint = @import("serial.zig").kprint;
const utils = @import("utils.zig");
const addr = @import("raspberryAddr.zig").iC;
const iC = @import("intController.zig");

pub fn irq_handler(exc: *iC.ExceptionFrame) callconv(.C) void {
    var irq_bank_0 = @intToPtr(*u32, addr.pendingBasic).*;
    var irq_bank_2 = @intToPtr(*u32, addr.pendingBasic).*;
    var irq_bank_1 = @intToPtr(*u32, addr.pendingBasic).*;

    // if interrupt is triggerd and all banks indaddrate 0, src is not supported(?)
    if (irq_bank_0 == 0 and irq_bank_1 == 0 and irq_bank_2 == 0) {
        var iss = @truncate(u25, exc.esr_el1);
        var il = @truncate(u1, exc.esr_el1 >> 25);
        var ec = @truncate(u6, exc.esr_el1 >> 26);
        var iss2 = @truncate(u5, exc.esr_el1 >> 32);
        _ = iss;
        _ = iss2;

        var ec_en = utils.intToEnum(iC.ExceptionClass, ec) catch {
            kprint("esp exception class not found \n", .{});
            return;
        };
        if (ec_en != iC.ExceptionClass.unknownReason) {
            kprint(".........INT............\n", .{});
            kprint("b0: {u} \n", .{irq_bank_0});
            kprint("b1: {u} \n", .{irq_bank_1});
            kprint("b2: {u} \n", .{irq_bank_2});

            kprint("Exception Class(from esp reg): {s} \n", .{@tagName(ec_en)});

            if (il == 1) {
                kprint("32 bit instruction trapped \n", .{});
            } else {
                kprint("16 bit instruction trapped \n", .{});
            }
            kprint(".........INT............\n", .{});
        }
    }
    // switch (irq_bank_0) {
    // 	addr::ARM_TIMER => {
    // 		// system timer
    // 		// todo => implement kernel timer
    // 		// kprint!("arm timer irq b0\n");
    // 		return;
    // 	},
    // 	addr::ARM_MAILBOX => {
    // 		kprint!("arm mailbox\n");
    // 	},
    // 	addr::ARM_DOORBELL_0 => {
    // 		kprint!("arm doorbell\n");
    // 	},
    // 	addr::ARM_DOORBELL_1 => {
    // 		kprint!("armm doorbell 1 b1\n");
    // 	},
    // 	addr::VPU0_HALTED => {},
    // 	addr::VPU1_HALTED => {},
    // 	addr::ILLEGAL_TYPE0 => {},
    // 	addr::ILLEGAL_TYPE1 => {},
    // 	// One or more bits set in pending register 1
    // 	addr::PENDING_1 => {
    // 		match irq_bank_1 {
    // 			// todo => implement timer
    // 			addr::TIMER0 => {},
    // 			addr::TIMER1 => {},
    // 			addr::TIMER2 => {},
    // 			addr::TIMER3 => {},
    // 			_ => {
    // 				kprint!("Unknown addr bank 1 irq num: {:#b} \n", irq_bank_1);
    // 			}
    // 		}

    // 	},
    // 	// One or more bits set in pending register 2
    // 	addr::PENDING_2 => {
    // 		match irq_bank_2 {
    // 			_ => {
    // 				kprint!("Unknown addr bank 2 irq num: {:#b} \n", irq_bank_2);
    // 			}
    // 		}
    // 	},
    // 	_ => {
    // 		kprint!("Unknown addr bank 0 irq num: {:#b} \n", irq_bank_0);
    // 	}
    // }
}
pub fn irq_elx_spx() callconv(.C) void {}
