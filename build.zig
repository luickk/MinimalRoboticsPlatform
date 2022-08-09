const std = @import("std");
const builtin = @import("builtin");
const warn = @import("std").debug.warn;
const os = @import("std").os;

pub fn build(b: *std.build.Builder) void {
    const exe = b.addExecutable("kernel", null);
    exe.setTarget(.{ .cpu_arch = std.Target.Cpu.Arch.aarch64, .os_tag = std.Target.Os.Tag.freestanding, .abi = std.Target.Abi.eabihf });
    var l = b.addOptions();
    l.addOption(bool, "is_qemu", true);
    exe.addOptions("build_options", l);
    exe.setBuildMode(std.builtin.Mode.ReleaseFast);

    exe.setLinkerScriptPath(std.build.FileSource{ .path = "src/linker.ld" });
    exe.addObjectFile("src/kernel.zig");
    exe.addCSourceFile("src/asm/adv_boot.S", &.{});
    exe.addCSourceFile("src/asm/exc_vec.S", &.{});

    exe.install();

    const qemu_no_disp = b.addSystemCommand(&.{ "qemu-system-aarch64", "-machine", "raspi3b", "-kernel", "zig-out/bin/kernel", "-serial", "stdio", "-display", "none" });
    qemu_no_disp.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        qemu_no_disp.addArgs(args);
    }

    const run_step_serial = b.step("qemu", "emulate the kernel with no graphics and output uart to console");
    run_step_serial.dependOn(&qemu_no_disp.step);

    const test_obj_step = b.addTest("src/utils.zig");
    const test_step = b.step("test", "Run tests for testable kernel parts");
    test_step.dependOn(&test_obj_step.step);
}
