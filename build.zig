const std = @import("std");
const builtin = @import("builtin");
const warn = @import("std").debug.warn;
const os = @import("std").os;

const Error = error{BlExceedsRomSize};

const BoardBuildConf = struct {
    boardName: []const u8,
    has_rom: bool,
    // the kernel is loaded by into 0x8000 ram by the gpu, so no relocation (or rom) required
    rom_start_addr: ?usize,
    bl_load_addr: ?usize,
    va_start: usize,
    qemu_launch_command: []const []const u8,
};

const raspi3b = BoardBuildConf {
    .boardName = "raspi3b",
    .has_rom = false,
    .rom_start_addr = null,
    // is duplicate and has to be changed here and in the runtime config file
    .va_start = 0xFFFFFF8000000000,
    // is duplicat and address to which the bl is loaded if there is NO rom(which is the case for the raspberry 3b)!
    // if there is rom, the bootloader must be loaded to 0x0 (and bl_load_addr = null)
    .bl_load_addr = 0x80000,
    // , "-d", "trace:bcm2835_systmr*", "-D", "./log.txt"
    .qemu_launch_command = &[_][]const u8{ "qemu-system-aarch64", "-machine", "raspi3b", "-device", "loader,addr=0x80000,file=zig-out/bin/bootloader.bin,cpu-num=0,force-raw=on", "-serial", "stdio", "-display", "none" },
};


const currBoard = raspi3b;
// const currBoard = qemuVirt;

const env_path = "src/environments/basicMultiProcess";
// const env_path = "src/environments/basicMultithreading";
// const env_path = "src/environments/multiProcAndThreading";
// const env_path = "src/environments/sysCallTopicsTest";
// const env_path = "src/environments/sharedMemTopicsTest";
// const env_path = "src/environments/waitTest";

// packages...
// SOC builtin features
var arm = std.build.Pkg{ .name = "arm", .source = .{ .path = "src/arm/arm.zig" } };
// package for kernel interfaces such as the timer or the interrupt controller or general drivers
var kpi = std.build.Pkg{ .name = "kpi", .source = .{ .path = "src/kpi/kpi.zig" } };
// functions generally required
var utils = std.build.Pkg{ .name = "utils", .source = .{ .path = "src/utils/utils.zig" } };
// board pkg contains the configuration "template"(boardConfig.zig) and different configuration files for different boards
var board = std.build.Pkg{ .name = "board", .source = .{ .path = "src/boards/" ++ currBoard.boardName ++ ".zig" } };
var environment = std.build.Pkg{ .name = "environment", .source = .{ .path = env_path ++ "/envConfig.zig" } };
// peripheral drivers
var periph = std.build.Pkg{ .name = "periph", .source = .{ .path = "src/periph/periph.zig" } };
// services that need to be accessed by kernel and other instances. the kernel allocator e.g.
var sharedKernelServices = std.build.Pkg{ .name = "sharedKernelServices", .source = .{ .path = "src/kernel/sharedKernelServices/sharedKernelServices.zig" } };
// package for all applications to call syscall
var appLib = std.build.Pkg{ .name = "appLib", .source = .{ .path = "src/appLib/appLib.zig" } };

//kernel threads
var kernelThreads = std.build.Pkg{ .name = "kernelThreads", .source = .{ .path = env_path ++ "/kernelThreads/threads.zig" } };

// driver packages
var interruptControllerDriver = std.build.Pkg{ .name = "interruptControllerDriver", .source = .{ .path = "src/boards/drivers/interruptController/interruptController.zig" } };
var timerDriver = std.build.Pkg{ .name = "timerDriver", .source = .{ .path = "src/boards/drivers/timer/timer.zig" } };


var sharedServices = std.build.Pkg{ .name = "sharedServices", .source = .{ .path = "src/sharedServices/sharedServices.zig" } };

pub fn build(b: *std.build.Builder) !void {
    // currBoard.config.checkConfig();    
    const build_mode = std.builtin.Mode.ReleaseFast;
    var build_options = b.addOptions();

    // inter package dependencies
    kernelThreads.dependencies = &.{ board, arm, sharedKernelServices, periph };
    kpi.dependencies = &.{ sharedKernelServices, arm };
    interruptControllerDriver.dependencies = &.{ board, arm };
    timerDriver.dependencies = &.{ board, utils };
    board.dependencies = &.{ kpi, utils, arm, interruptControllerDriver, timerDriver };
    sharedServices.dependencies = &.{ board, environment };
    sharedKernelServices.dependencies = &.{ board, environment, appLib, arm, utils, sharedServices, periph };
    periph.dependencies = &.{board};
    utils.dependencies = &.{ board, arm };
    arm.dependencies = &.{ periph, utils, board, sharedKernelServices };
    appLib.dependencies = &.{ board, utils, environment, sharedServices, sharedKernelServices };

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
    bl_exe.addCSourceFile("src/bootloader/board/" ++ currBoard.boardName ++ "/boot.S", &.{});
    bl_exe.addCSourceFile("src/bootloader/exc_vec.S", &.{});
    bl_exe.install();

    // kernel
    const kernel_exe = b.addExecutable("kernel", null);
    kernel_exe.force_pic = false;
    kernel_exe.pie = false;
    kernel_exe.code_model = .large;
    kernel_exe.strip = false;
    kernel_exe.addPackage(arm);
    kernel_exe.addPackage(sharedKernelServices);
    kernel_exe.addPackage(appLib);
    kernel_exe.addPackage(sharedServices);
    kernel_exe.addPackage(utils);
    kernel_exe.addPackage(kpi);
    kernel_exe.addPackage(board);
    kernel_exe.addPackage(environment);
    kernel_exe.addPackage(kernelThreads);
    kernel_exe.addPackage(periph);
    kernel_exe.addPackage(interruptControllerDriver);
    kernel_exe.addPackage(timerDriver);
    // kernel_exe.addAnonymousPackage("env-config", .{ .source_file = .{ .path = "src/configTemplates/envConfigTemplate.zig" } });
    // kernel_exe.addAnonymousModule("board-config", .{ .source_file = .{ .path = "src/configTemplates/boardConfigTemplate.zig" } });
    kernel_exe.setTarget(.{ .cpu_arch = std.Target.Cpu.Arch.aarch64, .os_tag = std.Target.Os.Tag.freestanding, .abi = std.Target.Abi.eabihf });
    kernel_exe.addOptions("build_options", build_options);
    kernel_exe.setBuildMode(build_mode);
    const temp_kernel_ld = "zig-cache/tmp/tempKernelLinker.ld";
    kernel_exe.setLinkerScriptPath(std.build.FileSource{ .path = temp_kernel_ld });
    kernel_exe.addObjectFile("src/kernel/kernel.zig");
    kernel_exe.addCSourceFile("src/kernel/exc_vec.S", &.{});
    kernel_exe.install();

    // compilation steps
    const update_linker_scripts_bl = UpdateLinkerScripts.create(b, .bootloader, temp_bl_ld, temp_kernel_ld, currBoard);
    const update_linker_scripts_k = UpdateLinkerScripts.create(b, .kernel, temp_bl_ld, temp_kernel_ld, currBoard);
    const delete_app_bins = b.addRemoveDirTree("src/kernel/bins");
    const scan_for_apps = ScanForApps.create(b, build_options);

    const build_and_run = b.step("qemu", "emulate the kernel with no graphics and output uart to console");
    const launch_with_gdb = b.option(bool, "gdb", "Launch qemu with -s -S to allow for net gdb debugging") orelse false;

    build_and_run.dependOn(&delete_app_bins.step);
    try setEnvironment(b, build_and_run, build_mode, env_path);

    build_and_run.dependOn(&update_linker_scripts_k.step);
    build_and_run.dependOn(&scan_for_apps.step);
    build_and_run.dependOn(&kernel_exe.install_step.?.step);
    build_and_run.dependOn(&kernel_exe.installRaw("kernel.bin", .{ .format = .bin, .dest_dir = .{ .custom = "../src/bootloader/bins/" } }).step);

    build_and_run.dependOn(&update_linker_scripts_bl.step);
    build_and_run.dependOn(&bl_exe.install_step.?.step);
    build_and_run.dependOn(&bl_exe.installRaw("bootloader.bin", .{ .format = .bin }).step);

    const qemu_launch_cmd = b.addSystemCommand(currBoard.qemu_launch_command);
    if (launch_with_gdb) {
        qemu_launch_cmd.addArg("-s");
        qemu_launch_cmd.addArg("-S");
    }
    build_and_run.dependOn(&qemu_launch_cmd.step);

    const clean = b.step("clean", "deletes zig-cache, zig-out, src/bootloader/bins/*, src/kernel/bins/*");
    const delete_zig_cache = b.addRemoveDirTree("zig-cache");
    const delete_zig_out = b.addRemoveDirTree("zig-out");
    const delete_bl_bins = b.addRemoveDirTree("src/bootloader/bins");
    const delete_k_bins = b.addRemoveDirTree("src/kernel/bins");
    const create_bins = CreateTmpSrcBins.create(b);

    clean.dependOn(&delete_zig_cache.step);
    clean.dependOn(&delete_zig_out.step);
    clean.dependOn(&delete_zig_cache.step);
    clean.dependOn(&delete_zig_out.step);
    clean.dependOn(&delete_bl_bins.step);
    clean.dependOn(&delete_k_bins.step);
    clean.dependOn(&delete_app_bins.step);
    clean.dependOn(&create_bins.step);
}

fn setEnvironment(b: *std.build.Builder, step: *std.build.Step, build_mode: std.builtin.Mode, comptime path: []const u8) !void {
    const user_apps_path = path ++ "/userApps/";
    var dir = try std.fs.cwd().openIterableDir(user_apps_path, .{});
    var it = dir.iterate();
    while (try it.next()) |folder| {
        if (folder.kind != .Directory) continue;
        const app = try addApp(b, build_mode, try std.fmt.allocPrint(b.allocator, "{s}/{s}", .{ user_apps_path, folder.name }));
        step.dependOn(&app.install_step.?.step);
        step.dependOn(&app.installRaw(try b.allocator.dupe(u8, folder.name), .{ .format = .bin, .dest_dir = .{ .custom = "../src/kernel/bins/apps/" } }).step);
    }
}

fn addApp(b: *std.build.Builder, build_mode: std.builtin.Mode, path: []const u8) !*std.build.LibExeObjStep {
    const app = b.addExecutable(std.fs.path.basename(path), null);
    app.force_pic = false;
    app.pie = false;
    app.setTarget(.{ .cpu_arch = std.Target.Cpu.Arch.aarch64, .os_tag = std.Target.Os.Tag.freestanding, .abi = std.Target.Abi.eabihf });
    app.setBuildMode(build_mode);
    app.setLinkerScriptPath(std.build.FileSource{ .path = try std.fmt.allocPrint(b.allocator, "{s}/linker.ld", .{path}) });
    app.addObjectFile(try std.fmt.allocPrint(b.allocator, "{s}/main.zig", .{path}));
    app.addPackage(periph);
    app.addPackage(board);
    app.addPackage(appLib);
    app.install();
    return app;
}

const UpdateLinkerScripts = struct {
    pub const ToUpdate = enum { bootloader, kernel };
    step: std.build.Step,
    temp_bl_ld: []const u8,
    temp_kernel_ld: []const u8,
    board_config: BoardBuildConf,
    to_update: ToUpdate,
    allocator: std.mem.Allocator,

    pub fn create(b: *std.build.Builder, to_update: ToUpdate, temp_bl_ld: []const u8, temp_kernel_ld: []const u8, board_config: BoardBuildConf) *UpdateLinkerScripts {
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
                var bl_start_address: usize = self.board_config.rom_start_addr orelse 0;
                if (!self.board_config.has_rom)
                    bl_start_address = self.board_config.bl_load_addr orelse 0;

                // // in case there is no rom(rom_size is equal to zero) and the kernel(and bl) are directly loaded to memory by some rom bootloader
                // // the ttbr0 memory is also identity mapped to the ram
                // var bl_pt_size_ttbr0: usize = (currBoard.config.mem.rom_size orelse 0) + currBoard.config.mem.ram_size;
                // if (!currBoard.config.mem.has_rom)
                //     bl_pt_size_ttbr0 = currBoard.config.mem.ram_size;

                try writeVarsToLinkerScript(self.allocator, "src/bootloader/linker.ld", self.temp_bl_ld, .{
                    bl_start_address,
                    null,
                    null,
                });
            },
            .kernel => {
                try writeVarsToLinkerScript(self.allocator, "src/kernel/linker.ld", self.temp_kernel_ld, .{
                    currBoard.va_start,
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

            var dir = std.fs.cwd().openIterableDir("src/kernel/bins/apps/", .{}) catch |e| {
                if (e == error.FileNotFound) {
                    self.build_options.addOption([]const []const u8, "apps", &.{});
                    return;
                } else {
                    return e;
                }
            };
            var it = dir.iterate();
            while (try it.next()) |file| {
                if (file.kind != .File) continue;
                try apps.append(file.name);
            }
            self.build_options.addOption([]const []const u8, "apps", apps.items);
        }
    }
};