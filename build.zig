const std = @import("std");
const builtin = @import("builtin");
const warn = @import("std").debug.warn;
const os = @import("std").os;

const Error = error{BlExceedsRomSize};

const raspi3b = @import("src/boards/raspi3b.zig");
const qemuVirt = @import("src/boards/qemuVirt.zig");

const currBoard = raspi3b;

// packages...
// SOC builtin features
var arm = std.build.Pkg{ .name = "arm", .source = .{ .path = "src/arm/arm.zig" } };
// functions generally required
var utils = std.build.Pkg{ .name = "utils", .source = .{ .path = "src/utils/utils.zig" } };
// board pkg contains the configuration "template"(boardConfig.zig) and different configuration files for different boards
var board = std.build.Pkg{ .name = "board", .source = .{ .path = "src/boards/" ++ @tagName(currBoard.config.board) ++ ".zig" } };
// peripheral drivers
var periph = std.build.Pkg{ .name = "periph", .source = .{ .path = "src/periph/periph.zig" } };
// services that need to be accessed by kernel and other instances. the kernel allocator e.g.
var sharedKServices = std.build.Pkg{ .name = "sharedKServices", .source = .{ .path = "src/kernel/sharedKServices/sharedKServices.zig" } };
// package for all applications to call syscall
var userSysCallInterface = std.build.Pkg{ .name = "userSysCallInterface", .source = .{ .path = "src/kernel/userSysCallInterface/userSysCallInterface.zig" } };

pub fn build(b: *std.build.Builder) !void {
    currBoard.config.checkConfig();
    const build_mode = std.builtin.Mode.ReleaseFast;
    var build_options = b.addOptions();

    // inter package dependencies
    sharedKServices.dependencies = &.{ board, build_options.*.getPackage("build_options"), arm, utils, periph };
    periph.dependencies = &.{board};
    utils.dependencies = &.{ board, arm };
    arm.dependencies = &.{ periph, utils, board, sharedKServices };

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
    bl_exe.addCSourceFile("src/bootloader/exc_vec.S", &.{});
    bl_exe.install();

    // kernel
    const kernel_exe = b.addExecutable("kernel", null);
    kernel_exe.force_pic = false;
    kernel_exe.pie = false;
    kernel_exe.code_model = .large;
    kernel_exe.strip = false;
    kernel_exe.addPackage(arm);
    kernel_exe.addPackage(sharedKServices);
    kernel_exe.addPackage(utils);
    kernel_exe.addPackage(board);
    kernel_exe.addPackage(periph);
    kernel_exe.setTarget(.{ .cpu_arch = std.Target.Cpu.Arch.aarch64, .os_tag = std.Target.Os.Tag.freestanding, .abi = std.Target.Abi.eabihf });
    kernel_exe.addOptions("build_options", build_options);
    kernel_exe.setBuildMode(build_mode);
    const temp_kernel_ld = "zig-cache/tmp/tempKernelLinker.ld";
    kernel_exe.setLinkerScriptPath(std.build.FileSource{ .path = temp_kernel_ld });
    kernel_exe.addObjectFile("src/kernel/kernel.zig");
    kernel_exe.addCSourceFile("src/kernel/exc_vec.S", &.{});
    kernel_exe.install();

    // compilation steps
    const update_linker_scripts_bl = UpdateLinkerScripts.create(b, .bootloader, temp_bl_ld, temp_kernel_ld, currBoard.config);
    const update_linker_scripts_k = UpdateLinkerScripts.create(b, .kernel, temp_bl_ld, temp_kernel_ld, currBoard.config);
    const scan_for_apps = ScanForApps.create(b, build_options);

    const build_and_run = b.step("qemu", "emulate the kernel with no graphics and output uart to console");
    const launch_with_gdb = b.option(bool, "gdb", "Launch qemu with -s -S to allow for net gdb debugging") orelse false;

    const app1 = try addApp(b, build_mode, "app1");
    build_and_run.dependOn(&app1.install_step.?.step);
    build_and_run.dependOn(&app1.installRaw("app1.bin", .{ .format = .bin, .dest_dir = .{ .custom = "../src/kernel/bins/" } }).step);

    const app2 = try addApp(b, build_mode, "app2");
    build_and_run.dependOn(&app2.install_step.?.step);
    build_and_run.dependOn(&app2.installRaw("app2.bin", .{ .format = .bin, .dest_dir = .{ .custom = "../src/kernel/bins/" } }).step);

    build_and_run.dependOn(&update_linker_scripts_k.step);
    build_and_run.dependOn(&scan_for_apps.step);
    build_and_run.dependOn(&kernel_exe.install_step.?.step);
    build_and_run.dependOn(&kernel_exe.installRaw("kernel.bin", .{ .format = .bin, .dest_dir = .{ .custom = "../src/bootloader/bins/" } }).step);

    build_and_run.dependOn(&update_linker_scripts_bl.step);
    build_and_run.dependOn(&bl_exe.install_step.?.step);
    build_and_run.dependOn(&bl_exe.installRaw("bootloader.bin", .{ .format = .bin }).step);

    const qemu_launch_cmd = b.addSystemCommand(currBoard.config.qemu_launch_command);
    if (launch_with_gdb) {
        qemu_launch_cmd.addArg("-s");
        qemu_launch_cmd.addArg("-S");
    }
    build_and_run.dependOn(&qemu_launch_cmd.step);

    const clean = b.step("clean", "deletes zig-cache, zig-out, src/bootloader/bins/*, src/kernel/bins/*");
    const delete_zig_cache = b.addRemoveDirTree("zig-cache");
    const delete_zig_out = b.addRemoveDirTree("zig-out");
    const delete_bl_bins = b.addRemoveDirTree("src/bootloader/bins");
    const delete_kernel_bins = b.addRemoveDirTree("src/kernel/bins");
    const create_bins = CreateTmpSrcBins.create(b);

    clean.dependOn(&delete_zig_cache.step);
    clean.dependOn(&delete_zig_out.step);
    clean.dependOn(&delete_zig_cache.step);
    clean.dependOn(&delete_zig_out.step);
    clean.dependOn(&delete_bl_bins.step);
    clean.dependOn(&delete_kernel_bins.step);
    clean.dependOn(&create_bins.step);
}

fn addApp(b: *std.build.Builder, build_mode: std.builtin.Mode, comptime name: []const u8) !*std.build.LibExeObjStep {
    const app = b.addExecutable(name, null);
    app.force_pic = false;
    app.pie = false;
    app.setTarget(.{ .cpu_arch = std.Target.Cpu.Arch.aarch64, .os_tag = std.Target.Os.Tag.freestanding, .abi = std.Target.Abi.eabihf });
    app.setBuildMode(build_mode);
    app.setLinkerScriptPath(std.build.FileSource{ .path = "src/apps/" ++ name ++ "/linker.ld" });
    app.addObjectFile("src/apps/" ++ name ++ "/main.zig");
    app.addPackage(periph);
    app.addPackage(userSysCallInterface);
    app.install();
    return app;
}

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
            .step = std.build.Step.init(.custom, "UpdateLinkerScript", b.allocator, UpdateLinkerScripts.doStep),
            .temp_bl_ld = temp_bl_ld,
            .temp_kernel_ld = temp_kernel_ld,
            .board_config = board_config,
            .to_update = to_update,
            .allocator = b.allocator,
        };
        return self;
    }

    /// inserts args variables (in order), defined in inp_linker_script_path in outp_linker_script_path
    // bc file reads cannot be comptime (and the loop not be unrolled), arr size is static and elements optional
    // if more args are required just increase arr size (will have to pad all fn calls with fewer args in list!.)
    fn writeVarsToLinkerScript(a: std.mem.Allocator, inp_linker_script_path: []const u8, outp_linker_script_path: []const u8, args: [3]?usize) !void {
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

const CreateTmpSrcBins = struct {
    step: std.build.Step,

    pub fn create(b: *std.build.Builder) *CreateTmpSrcBins {
        const self = b.allocator.create(CreateTmpSrcBins) catch unreachable;
        self.* = .{ .step = std.build.Step.init(.custom, "CreateTmpSrcBins", b.allocator, CreateTmpSrcBins.doStep) };
        return self;
    }

    fn doStep(step: *std.build.Step) !void {
        _ = step;
        try std.fs.cwd().makeDir("src/kernel/bins/");
        try std.fs.cwd().makeDir("src/bootloader/bins/");
    }
};

const ScanForApps = struct {
    step: std.build.Step,
    builder: *std.build.Builder,
    build_options: *std.build.OptionsStep,

    pub fn create(b: *std.build.Builder, build_options: *std.build.OptionsStep) *ScanForApps {
        const self = b.allocator.create(ScanForApps) catch unreachable;
        self.* = .{ .step = std.build.Step.init(.custom, "ScanForApps", b.allocator, ScanForApps.doStep), .builder = b, .build_options = build_options };
        return self;
    }

    fn doStep(step: *std.build.Step) !void {
        const self = @fieldParentPtr(ScanForApps, "step", step);
        // searching for apps in apps/
        {
            var apps = std.ArrayList([]const u8).init(self.builder.allocator);
            defer apps.deinit();

            var dir = try std.fs.cwd().openIterableDir("src/kernel/bins/", .{});
            var it = dir.iterate();
            while (try it.next()) |file| {
                if (file.kind != .File) {
                    continue;
                }
                try apps.append(file.name);
            }
            self.build_options.addOption([]const []const u8, "apps", apps.items);
        }
    }
};
