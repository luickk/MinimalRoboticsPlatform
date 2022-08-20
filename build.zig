const std = @import("std");
const builtin = @import("builtin");
const warn = @import("std").debug.warn;
const os = @import("std").os;

pub fn build(b: *std.build.Builder) !void {
    var build_options = b.addOptions();
    build_options.addOption(bool, "is_qemu", true);

    var peripherals = std.build.Pkg{ .name = "peripherals", .path = .{ .path = "src/peripherals/peripherals.zig" } };
    var utils = std.build.Pkg{ .name = "utils", .path = .{ .path = "src/utils/utils.zig" } };

    // bootloader
    const bl_exe = b.addExecutable("bootloader", null);
    bl_exe.addPackage(peripherals);
    bl_exe.addPackage(utils);

    bl_exe.setTarget(.{ .cpu_arch = std.Target.Cpu.Arch.aarch64, .os_tag = std.Target.Os.Tag.freestanding, .abi = std.Target.Abi.eabihf });
    bl_exe.addOptions("build_options", build_options);
    bl_exe.setBuildMode(std.builtin.Mode.ReleaseSafe);
    bl_exe.setLinkerScriptPath(std.build.FileSource{ .path = "src/bootloader/linker.ld" });
    bl_exe.force_pic = false;
    bl_exe.linkage = std.build.LibExeObjStep.Linkage.static;
    // bl_exe.link_eh_frame_hdr = true;
    // bl_exe.link_emit_relocs = true;
    // bl_exe.pie = true;
    // bl_exe.link_z_notext = true;
    bl_exe.addObjectFile("src/bootloader/main.zig");
    bl_exe.addCSourceFile("src/bootloader/asm/adv_boot.S", &.{});
    bl_exe.addCSourceFile("src/bootloader/asm/exc_vec.S", &.{});
    // std.build.InstallRawStep.CreateOptions{}
    // bl_exe.install();
    bl_exe.installRaw("bootloader.bin", .{ .format = std.build.InstallRawStep.RawFormat.bin }).artifact.install();

    // kernel
    const kernel_exe = b.addExecutable("kernel", null);
    kernel_exe.addPackage(peripherals);
    kernel_exe.addPackage(utils);
    kernel_exe.setTarget(.{ .cpu_arch = std.Target.Cpu.Arch.aarch64, .os_tag = std.Target.Os.Tag.freestanding, .abi = std.Target.Abi.eabihf });
    kernel_exe.addOptions("build_options", build_options);
    kernel_exe.setBuildMode(std.builtin.Mode.ReleaseSafe);
    kernel_exe.setLinkerScriptPath(std.build.FileSource{ .path = "src/kernel/linker.ld" });
    kernel_exe.addObjectFile("src/kernel/kernel.zig");
    // kernel_exe.install();
    bl_exe.installRaw("kernel.bin", .{ .format = std.build.InstallRawStep.RawFormat.bin }).artifact.install();

    try concatBins("zig-out/bin/kernel.bin", "zig-out/bin/bootloader.bin", "zig-out/bin/mergedKernel");

    const qemu_no_disp = b.addSystemCommand(&.{ "qemu-system-aarch64", "-machine", "raspi3b", "-kernel", "zig-out/bin/bootloader.bin", "-serial", "stdio", "-display", "none" });
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

fn concatBins(f1: []const u8, f2: []const u8, out_file_path: []const u8) !void {
    var f1_opened = try std.fs.cwd().openFile(f1, .{});
    var in_stream_1 = std.io.bufferedReader(f1_opened.reader()).reader();
    defer f1_opened.close();

    var f2_opened = try std.fs.cwd().openFile(f2, .{});
    var in_stream_2 = std.io.bufferedReader(f2_opened.reader()).reader();
    defer f2_opened.close();

    var f_concated = try std.fs.cwd().createFile(out_file_path, .{ .read = true });
    defer f_concated.close();

    var buf: [1024]u8 = undefined;
    var read_size: usize = 0;
    while (read_size >= buf.len) {
        read_size = try in_stream_1.readAll(&buf);
        _ = try f_concated.write(buf[0..read_size]);
    }
    read_size = 0;
    while (read_size >= buf.len) {
        read_size = try in_stream_2.readAll(&buf);
        _ = try f_concated.write(buf[0..read_size]);
    }
}
