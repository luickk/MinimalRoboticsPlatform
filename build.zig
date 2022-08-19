const std = @import("std");
const builtin = @import("builtin");
const warn = @import("std").debug.warn;
const os = @import("std").os;

pub fn build(b: *std.build.Builder) void {

    // bootloader
    const bl_exe = b.addExecutable("bootloader", null);
    bl_exe.addPackagePath("peripherals", "src/peripherals/peripherals.zig");

    bl_exe.setTarget(.{ .cpu_arch = std.Target.Cpu.Arch.aarch64, .os_tag = std.Target.Os.Tag.freestanding, .abi = std.Target.Abi.eabihf });
    var build_options = b.addOptions();
    build_options.addOption(bool, "is_qemu", true);
    bl_exe.addOptions("build_options", build_options);
    bl_exe.setBuildMode(std.builtin.Mode.ReleaseSafe);

    bl_exe.setLinkerScriptPath(std.build.FileSource{ .path = "src/bootloader/linker.ld" });

    // bl_exe.force_pic = true;
    // bl_exe.link_eh_frame_hdr = true;
    // bl_exe.link_emit_relocs = true;
    // bl_exe.pie = true;
    // bl_exe.link_z_notext = true;

    bl_exe.addObjectFile("src/bootloader/main.zig");
    bl_exe.addCSourceFile("src/bootloader/asm/adv_boot.S", &.{});
    bl_exe.addCSourceFile("src/bootloader/asm/exc_vec.S", &.{});

    bl_exe.install();

    const qemu_no_disp = b.addSystemCommand(&.{ "qemu-system-aarch64", "-machine", "raspi3b", "-kernel", "zig-out/bin/bootloader", "-serial", "stdio", "-display", "none" });
    qemu_no_disp.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        qemu_no_disp.addArgs(args);
    }
    const run_step_serial = b.step("qemu", "emulate the kernel with no graphics and output uart to console");
    run_step_serial.dependOn(&qemu_no_disp.step);

    const qemu_gdb_no_disp = b.addSystemCommand(&.{ "qemu-system-aarch64", "-s", "-S", "-machine", "raspi3b", "-kernel", "zig-out/bin/bootloader", "-serial", "stdio", "-display", "none" });
    qemu_gdb_no_disp.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        qemu_gdb_no_disp.addArgs(args);
    }
    const run_step_serial_gdb = b.step("qemu-gdb", "emulate the kernel with no graphics and output uart to console");
    run_step_serial_gdb.dependOn(&qemu_gdb_no_disp.step);

    const test_obj_step = b.addTest("src/utils.zig");
    const test_step = b.step("test", "Run tests for testable kernel parts");
    test_step.dependOn(&test_obj_step.step);
}
