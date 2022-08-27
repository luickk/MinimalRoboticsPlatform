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
    bl_exe.setBuildMode(std.builtin.Mode.ReleaseFast);
    bl_exe.setLinkerScriptPath(std.build.FileSource{ .path = "src/bootloader/linker.ld" });
    bl_exe.code_model = .large;
    bl_exe.force_pic = false;
    bl_exe.linkage = .static;
    bl_exe.addObjectFile("src/bootloader/main.zig");
    bl_exe.addCSourceFile("src/bootloader/asm/adv_boot.S", &.{});
    bl_exe.addCSourceFile("src/bootloader/asm/exc_vec.S", &.{});
    bl_exe.addCSourceFile("src/bootloader/asm/mmu.S", &.{});
    bl_exe.install();
    bl_exe.installRaw("bootloader.bin", .{ .format = std.build.InstallRawStep.RawFormat.bin, .pad_to_size = 502404 }).artifact.install();

    // kernel
    const kernel_exe = b.addExecutable("kernel", null);
    kernel_exe.addPackage(peripherals);
    kernel_exe.addPackage(utils);
    kernel_exe.setTarget(.{ .cpu_arch = std.Target.Cpu.Arch.aarch64, .os_tag = std.Target.Os.Tag.freestanding, .abi = std.Target.Abi.eabihf });
    kernel_exe.addOptions("build_options", build_options);
    kernel_exe.setBuildMode(std.builtin.Mode.ReleaseFast);
    kernel_exe.force_pic = false;
    kernel_exe.code_model = .large;
    kernel_exe.linkage = .static;
    kernel_exe.setLinkerScriptPath(std.build.FileSource{ .path = "src/kernel/linker.ld" });
    kernel_exe.addObjectFile("src/kernel/kernel.zig");
    kernel_exe.install();
    kernel_exe.installRaw("kernel.bin", .{ .format = std.build.InstallRawStep.RawFormat.bin }).artifact.install();

    var qemu_args = [_][]const u8{ "qemu-system-aarch64", "-machine", "raspi3b", "-device", "loader,file=zig-out/bin/mergedKernel,cpu-num=0,force-raw=on", "-serial", "stdio", "-display", "none" };
    var concatStep = ConcateBinsStep.create(b, "zig-out/bin/bootloader.bin", "zig-out/bin/kernel.bin", "zig-out/bin/mergedKernel");

    const run_step_serial = b.step("qemu", "emulate the kernel with no graphics and output uart to console");
    run_step_serial.dependOn(b.getInstallStep());
    run_step_serial.dependOn(&concatStep.step);
    run_step_serial.dependOn(&b.addSystemCommand(&qemu_args).step);

    const run_step_serial_gdb = b.step("qemu-gdb", "emulate the kernel with no graphics and output uart to console");
    var gdb_qemu = b.addSystemCommand(&qemu_args);
    gdb_qemu.addArg("-s");
    gdb_qemu.addArg("-S");
    run_step_serial_gdb.dependOn(b.getInstallStep());
    run_step_serial_gdb.dependOn(&concatStep.step);
    run_step_serial_gdb.dependOn(&gdb_qemu.step);

    const test_obj_step = b.addTest("src/utils.zig");
    const test_step = b.step("test", "Run tests for testable kernel parts");
    test_step.dependOn(&test_obj_step.step);
}

const ConcateBinsStep = struct {
    step: std.build.Step,
    f1_path: []const u8,
    f2_path: []const u8,
    out_file_path: []const u8,

    pub fn create(b: *std.build.Builder, f1: []const u8, f2: []const u8, out_file_path: []const u8) *ConcateBinsStep {
        const self = b.allocator.create(ConcateBinsStep) catch unreachable;
        self.* = .{
            .step = std.build.Step.init(.custom, "binConcat", b.allocator, ConcateBinsStep.doStep),
            .f1_path = f1,
            .f2_path = f2,
            .out_file_path = out_file_path,
        };
        return self;
    }

    fn doStep(step: *std.build.Step) !void {
        const self = @fieldParentPtr(ConcateBinsStep, "step", step);
        var f1_opened = try std.fs.cwd().openFile(self.f1_path, .{});
        var in_stream_1 = std.io.bufferedReader(f1_opened.reader()).reader();
        defer f1_opened.close();
        // std.debug.print("bootloader size: {d} \n", .{(try f1_opened.stat()).size});

        var f2_opened = try std.fs.cwd().openFile(self.f2_path, .{});
        var in_stream_2 = std.io.bufferedReader(f2_opened.reader()).reader();
        defer f2_opened.close();
        // std.debug.print("kernel size: {d} \n", .{(try f2_opened.stat()).size});

        var f_concated = try std.fs.cwd().createFile(self.out_file_path, .{ .read = true });
        defer f_concated.close();

        var buf = [_]u8{0} ** 1024;
        var read_size: usize = 0;
        var at: usize = 0;
        while (true) {
            read_size = try in_stream_1.readAll(&buf);
            try f_concated.writeAll(buf[0..read_size]);
            at += read_size;
            if (read_size < buf.len) break;
        }
        while (true) {
            read_size = try in_stream_2.readAll(&buf);
            try f_concated.writeAll(buf[0..read_size]);
            if (read_size < buf.len) break;
        }
    }
};
