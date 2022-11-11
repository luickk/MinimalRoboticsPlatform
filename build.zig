const std = @import("std");
const builtin = @import("builtin");
const warn = @import("std").debug.warn;
const os = @import("std").os;

const Error = error{BlExceedsRomSize};

const raspi3b = @import("src/boards/raspi3b.zig");
const qemuVirt = @import("src/boards/qemuVirt.zig");

const currBoard = qemuVirt;

// both binaries are padded to that size and zig throws an exception if too small.
const kernel_bin_size: usize = 0x2000000;
const bl_bin_size: usize = 0x2000000;

pub fn build(b: *std.build.Builder) !void {
    currBoard.config.checkConfig();
    const build_mode = std.builtin.Mode.ReleaseFast;

    var build_options = b.addOptions();
    build_options.addOption(usize, "kernel_bin_size", kernel_bin_size);
    build_options.addOption(usize, "bl_bin_size", bl_bin_size);

    // SOC builtin features
    var arm = std.build.Pkg{ .name = "arm", .source = .{ .path = "src/arm/arm.zig" } };
    // functions generally required
    var utils = std.build.Pkg{ .name = "utils", .source = .{ .path = "src/utils/utils.zig" } };
    // board pkg contains the configuration "template"(boardConfig.zig) and different configuration files for different boards
    var board = std.build.Pkg{ .name = "board", .source = .{ .path = "src/boards/" ++ @tagName(currBoard.config.board) ++ ".zig" } };
    // peripheral drivers
    var periph = std.build.Pkg{ .name = "periph", .source = .{ .path = "src/periph/periph.zig" } };

    periph.dependencies = &.{board};

    arm.dependencies = &.{periph};
    arm.dependencies = &.{board};

    // bootloader
    const bl_exe = b.addExecutable("bootloader", null);
    bl_exe.force_pic = false;
    bl_exe.pie = false;
    bl_exe.code_model = .large;
    bl_exe.addPackage(arm);
    bl_exe.addPackage(utils);
    bl_exe.addPackage(board);
    bl_exe.addPackage(periph);
    bl_exe.setTarget(.{ .cpu_arch = std.Target.Cpu.Arch.aarch64, .os_tag = std.Target.Os.Tag.freestanding, .abi = std.Target.Abi.eabihf });
    bl_exe.addOptions("build_options", build_options);
    bl_exe.setBuildMode(build_mode);
    const temp_bl_ld = "zig-cache/tmp/tempBlLinker.ld";
    bl_exe.setLinkerScriptPath(std.build.FileSource{ .path = temp_bl_ld });
    bl_exe.addObjectFile("src/bootloader/bootloader.zig");
    bl_exe.addCSourceFile("src/bootloader/board/" ++ @tagName(currBoard.config.board) ++ "/boot.S", &.{});
    bl_exe.addCSourceFile("src/bootloader/board/" ++ @tagName(currBoard.config.board) ++ "/exc_vec.S", &.{});
    bl_exe.install();
    if (currBoard.config.mem.rom_size) |rs|
        if (bl_bin_size + kernel_bin_size > rs)
            return Error.BlExceedsRomSize;

    // kernel
    const kernel_exe = b.addExecutable("kernel", null);
    kernel_exe.force_pic = false;
    kernel_exe.pie = false;
    kernel_exe.code_model = .large;
    kernel_exe.strip = false;
    kernel_exe.addPackage(arm);
    kernel_exe.addPackage(utils);
    kernel_exe.addPackage(board);
    kernel_exe.addPackage(periph);
    kernel_exe.setTarget(.{ .cpu_arch = std.Target.Cpu.Arch.aarch64, .os_tag = std.Target.Os.Tag.freestanding, .abi = std.Target.Abi.eabihf });
    kernel_exe.addOptions("build_options", build_options);
    kernel_exe.setBuildMode(build_mode);
    const temp_kernel_ld = "zig-cache/tmp/tempKernelLinker.ld";
    kernel_exe.setLinkerScriptPath(std.build.FileSource{ .path = temp_kernel_ld });
    kernel_exe.addObjectFile("src/kernel/kernel.zig");
    kernel_exe.install();

    // compilation steps
    var concat_step = ConcateBinsStep.create(b, "zig-out/bin/bootloader.bin", "zig-out/bin/kernel.bin", "zig-out/bin/mergedKernel");
    var update_linker_scripts_bl = UpdateLinkerScripts.create(b, .bootloader, temp_bl_ld, temp_kernel_ld, currBoard.config);
    var update_linker_scripts_k = UpdateLinkerScripts.create(b, .kernel, temp_bl_ld, temp_kernel_ld, currBoard.config);
    const run_step_serial = b.step("qemu", "emulate the kernel with no graphics and output uart to console");
    // run_step_serial.dependOn(b.getInstallStep());
    run_step_serial.dependOn(&update_linker_scripts_bl.step);
    // compiling elfs as well, but only for gdb debugging
    run_step_serial.dependOn(&bl_exe.install_step.?.step);
    run_step_serial.dependOn(&bl_exe.installRaw("bootloader.bin", .{ .format = .bin, .pad_to_size = bl_bin_size }).step);
    run_step_serial.dependOn(&update_linker_scripts_k.step);
    run_step_serial.dependOn(&kernel_exe.install_step.?.step);
    run_step_serial.dependOn(&kernel_exe.installRaw("kernel.bin", .{ .format = .bin, .pad_to_size = kernel_bin_size }).step);
    run_step_serial.dependOn(&concat_step.step);
    run_step_serial.dependOn(&b.addSystemCommand(currBoard.config.qemu_launch_command).step);

    const run_step_serial_gdb = b.step("qemu-gdb", "emulate the kernel with no graphics and output uart to console");
    var gdb_qemu = b.addSystemCommand(currBoard.config.qemu_launch_command);
    gdb_qemu.addArg("-s");
    gdb_qemu.addArg("-S");
    run_step_serial_gdb.dependOn(&update_linker_scripts_bl.step);
    // compiling elfs as well, but only for gdb debugging
    run_step_serial_gdb.dependOn(&bl_exe.install_step.?.step);
    run_step_serial_gdb.dependOn(&bl_exe.installRaw("bootloader.bin", .{ .format = .bin, .pad_to_size = bl_bin_size }).step);
    run_step_serial_gdb.dependOn(&update_linker_scripts_k.step);
    run_step_serial_gdb.dependOn(&kernel_exe.install_step.?.step);
    run_step_serial_gdb.dependOn(&kernel_exe.installRaw("kernel.bin", .{ .format = .bin, .pad_to_size = kernel_bin_size }).step);
    run_step_serial_gdb.dependOn(&concat_step.step);
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
        var in_stream_1_ = std.io.bufferedReader(f1_opened.reader());
        var in_stream_1 = in_stream_1_.reader();
        defer f1_opened.close();
        // std.debug.print("bootloader size: {d} \n", .{(try f1_opened.stat()).size});

        var f2_opened = try std.fs.cwd().openFile(self.f2_path, .{});
        var in_stream_2_ = std.io.bufferedReader(f2_opened.reader());
        var in_stream_2 = in_stream_2_.reader();
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

/// concatenates two files to one. (f1+f2)
const UpdateLinkerScripts = struct {
    pub const ToUpdate = enum { bootloader, kernel };
    step: std.build.Step,
    temp_bl_ld: []const u8,
    temp_kernel_ld: []const u8,
    board_config: currBoard.boardConfig.BoardConfig,
    to_update: ToUpdate,
    allocator: std.mem.Allocator,

    pub fn create(b: *std.build.Builder, to_update: ToUpdate, temp_bl_ld: []const u8, temp_kernel_ld: []const u8, board_config: currBoard.boardConfig.BoardConfig) *UpdateLinkerScripts {
        const self = b.allocator.create(UpdateLinkerScripts) catch unreachable;
        self.* = .{
            .step = std.build.Step.init(.custom, "binConcat", b.allocator, UpdateLinkerScripts.doStep),
            .temp_bl_ld = temp_bl_ld,
            .temp_kernel_ld = temp_kernel_ld,
            .board_config = board_config,
            .to_update = to_update,
            .allocator = b.allocator,
        };
        return self;
    }

    fn doStep(step: *std.build.Step) !void {
        const self = @fieldParentPtr(UpdateLinkerScripts, "step", step);
        switch (self.to_update) {
            .bootloader => {
                var bl_start_address: usize = self.board_config.mem.rom_start_addr orelse 0;
                if (!self.board_config.mem.has_rom)
                    bl_start_address = self.board_config.mem.bl_load_addr orelse 0;

                // in case there is no rom(rom_size is equal to zero) and the kernel(and bl) are directly loaded to memory by some rom bootloader
                // the ttbr0 memory is also identity mapped to the ram
                var bl_pt_size_ttbr0: usize = (currBoard.config.mem.rom_size orelse 0) + currBoard.config.mem.ram_size;
                if (!currBoard.config.mem.has_rom)
                    bl_pt_size_ttbr0 = currBoard.config.mem.ram_size;

                try writeVarsToLinkerScript(self.allocator, "src/bootloader/linker.ld", self.temp_bl_ld, .{
                    bl_start_address,
                    null,
                    null,
                });
            },
            .kernel => {
                try writeVarsToLinkerScript(self.allocator, "src/kernel/linker.ld", self.temp_kernel_ld, .{
                    currBoard.config.mem.va_start,
                    null,
                    null,
                });
            },
        }
    }
};

fn getFileSize(path: []const u8) !usize {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return (try file.stat()).size;
}

/// inserts args variables (in order), defined in inp_linker_script_path in outp_linker_script_path
// bc file reads cannot be comptime (and the loop not be unrolled), arr size is static and elements optional
// if more args are required just increase arr size (will have to pad all fn calls with fewer args in list!.)
pub fn writeVarsToLinkerScript(a: std.mem.Allocator, inp_linker_script_path: []const u8, outp_linker_script_path: []const u8, args: [3]?usize) !void {
    var in_file = try std.fs.cwd().openFile(inp_linker_script_path, .{});
    defer in_file.close();
    var buf_reader = std.io.bufferedReader(in_file.reader());
    var in_stream = buf_reader.reader();

    const out_file = try std.fs.cwd().createFile(outp_linker_script_path, .{});
    defer out_file.close();

    var buf: [1024]u8 = undefined;
    var args_conv_buff: [1024]u8 = undefined;
    var args_i: usize = 0;
    var outp_line = std.ArrayList(u8).init(a);
    var j: usize = 0;
    var to_insert: []u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        try outp_line.appendSlice(line);
        for (line) |c, i| {
            if (c == '{' and i + 4 <= line.len) {
                if (std.mem.eql(u8, line[i .. i + 6], "{@zig}")) {
                    while (j < 6) : (j += 1) {
                        _ = outp_line.orderedRemove(i);
                    }
                    j = 0;
                    if (args[args_i]) |arg| {
                        to_insert = std.fmt.bufPrintIntToSlice(&args_conv_buff, arg, 10, .lower, .{});
                        try outp_line.insertSlice(i, to_insert);
                    } else {
                        return (error{TooFewArgs}).TooFewArgs;
                    }
                    args_i += 1;
                }
            }
        }
        try out_file.writeAll(outp_line.items);
        try out_file.writeAll("\n");
        outp_line.clearAndFree();
    }
}
