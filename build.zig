const std = @import("std");
const builtin = @import("builtin");
const warn = @import("std").debug.warn;
const os = @import("std").os;

const BoardParams = struct {
    const BoardMemLayout = struct {
        rom_start_addr: usize,
        rom_len: usize,

        ram_start_addr: usize,
        ram_len: usize,

        storage_start_addr: usize,
        storage_len: usize,
    };
    pub const BoardType = enum {
        raspi3b,
        virt,
    };
    board: BoardType,
    mem: BoardMemLayout,
    path_name: []const u8,
    qemu_launch_command: []const []const u8,
    // todo => pg_dir_size
};

const Error = error{BlExceedsRomSize};

const Boards = struct {
    pub const raspi3b = BoardParams{
        .board = .raspi3b,
        .mem = BoardParams.BoardMemLayout{ .rom_start_addr = 0, .rom_len = 0x500000, .ram_start_addr = 0x500000, .ram_len = 0x40000000, .storage_start_addr = 0, .storage_len = 0 },
        .path_name = "raspi3b",
        .qemu_launch_command = &[_][]const u8{ "qemu-system-aarch64", "-machine", "raspi3b", "-device", "loader,file=zig-out/bin/mergedKernel,cpu-num=0,force-raw=on", "-serial", "stdio", "-display", "none" },
    };
};

pub fn build(b: *std.build.Builder) !void {
    const curr_board = Boards.raspi3b;

    var build_options = b.addOptions();
    build_options.addOption(BoardParams.BoardType, "curr_board_type", curr_board.board);
    build_options.addOption([]const u8, "curr_board_path_name", curr_board.path_name);
    build_options.addOption(usize, "ram_start_addr", curr_board.mem.ram_start_addr);
    build_options.addOption(usize, "rom_start_addr", curr_board.mem.rom_start_addr);
    build_options.addOption(usize, "ram_len", curr_board.mem.ram_len);
    build_options.addOption(usize, "rom_len", curr_board.mem.rom_len);

    var peripherals = std.build.Pkg{ .name = "peripherals", .source = .{ .path = "src/peripherals/peripherals.zig" } };
    var addresses = std.build.Pkg{ .name = "addresses", .source = .{ .path = "src/addresses/" ++ curr_board.path_name ++ ".zig" } };
    peripherals.dependencies = &.{addresses};
    addresses.dependencies = &.{build_options.getPackage("build_options")};
    var utils = std.build.Pkg{ .name = "utils", .source = .{ .path = "src/utils/utils.zig" } };
    utils.dependencies = &.{addresses};

    // kernel
    const kernel_exe = b.addExecutable("kernel", null);
    kernel_exe.addPackage(peripherals);
    kernel_exe.addPackage(addresses);
    kernel_exe.addPackage(utils);
    kernel_exe.setTarget(.{ .cpu_arch = std.Target.Cpu.Arch.aarch64, .os_tag = std.Target.Os.Tag.freestanding, .abi = std.Target.Abi.eabihf });
    kernel_exe.addOptions("build_options", build_options);
    kernel_exe.setBuildMode(std.builtin.Mode.ReleaseFast);
    kernel_exe.setLinkerScriptPath(std.build.FileSource{ .path = "src/kernel/linker.ld" });
    kernel_exe.addObjectFile("src/kernel/kernel.zig");
    kernel_exe.install();
    kernel_exe.installRaw("kernel.bin", .{ .format = std.build.InstallRawStep.RawFormat.bin }).artifact.install();
    const kernel_bin_size = try getFileSize("zig-out/bin/kernel.bin");
    build_options.addOption(usize, "kernel_bin_size", kernel_bin_size);

    // bootloader
    const bl_exe = b.addExecutable("bootloader", null);
    bl_exe.addPackage(peripherals);
    bl_exe.addPackage(addresses);
    bl_exe.addPackage(utils);

    bl_exe.setTarget(.{ .cpu_arch = std.Target.Cpu.Arch.aarch64, .os_tag = std.Target.Os.Tag.freestanding, .abi = std.Target.Abi.eabihf });
    bl_exe.addOptions("build_options", build_options);
    bl_exe.setBuildMode(std.builtin.Mode.ReleaseFast);
    bl_exe.setLinkerScriptPath(std.build.FileSource{ .path = "src/bootloader/linker.ld" });
    bl_exe.addObjectFile("src/bootloader/bootloader.zig");
    bl_exe.addCSourceFile("src/bootloader/board/" ++ curr_board.path_name ++ "/boot.S", &.{});
    bl_exe.addCSourceFile("src/bootloader/board/" ++ curr_board.path_name ++ "/exc_vec.S", &.{});
    bl_exe.install();
    bl_exe.installRaw("bootloader.bin", .{ .format = std.build.InstallRawStep.RawFormat.bin }).artifact.install();
    const bl_bin_size = try getFileSize("zig-out/bin/bootloader.bin");

    // todo => kernel bin file size way too big
    if (bl_bin_size + kernel_bin_size > curr_board.mem.rom_len)
        return Error.BlExceedsRomSize;

    var concatStep = ConcateBinsStep.create(b, "zig-out/bin/bootloader.bin", "zig-out/bin/kernel.bin", "zig-out/bin/mergedKernel");

    const run_step_serial = b.step("qemu", "emulate the kernel with no graphics and output uart to console");
    run_step_serial.dependOn(b.getInstallStep());
    run_step_serial.dependOn(&concatStep.step);
    run_step_serial.dependOn(&b.addSystemCommand(curr_board.qemu_launch_command).step);

    const run_step_serial_gdb = b.step("qemu-gdb", "emulate the kernel with no graphics and output uart to console");
    var gdb_qemu = b.addSystemCommand(curr_board.qemu_launch_command);
    gdb_qemu.addArg("-s");
    gdb_qemu.addArg("-S");
    run_step_serial_gdb.dependOn(b.getInstallStep());
    run_step_serial_gdb.dependOn(&concatStep.step);
    run_step_serial_gdb.dependOn(&gdb_qemu.step);

    const test_obj_step = b.addTest("src/utils.zig");
    const test_step = b.step("test", "Run tests for testable kernel parts");
    test_step.dependOn(&test_obj_step.step);
}

/// concatenates two files to one. (f1+f2)
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

fn getFileSize(path: []const u8) !usize {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return (try file.stat()).size;
}
