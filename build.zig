const std = @import("std");
const warn = std.debug.warn;
const os = std.os;

const BoardBuildConf = @import("src/configTemplates/boardBuildConfigTemplate.zig").BoardBuildConf;
const builtin = @import("builtin");

const Error = error{BlExceedsRomSize};

const Module = std.build.Module;
const ModuleDependency = std.build.ModuleDependency;

const raspi3b = BoardBuildConf{
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

const qemuVirt = BoardBuildConf{
    .boardName = "qemuVirt",
    .has_rom = true,
    // qemus virt machine has no rom
    .rom_start_addr = 0,
    // is duplicate and has to be changed here and in the runtime config file
    .va_start = 0xFFFFFF8000000000,
    // is duplicat and address to which the bl is loaded if there is NO rom(which is the case for the raspberry 3b)!
    // if there is rom, the bootloader must be loaded to 0x0 (and bl_load_addr = null)
    .bl_load_addr = null,
    // arm_gt, gic
    // "-d", "trace:gic*", "-D", "./log.txt"
    .qemu_launch_command = &[_][]const u8{ "qemu-system-aarch64", "-machine", "virt", "-m", "10G", "-cpu", "cortex-a53", "-device", "loader,file=zig-out/bin/bootloader.bin,cpu-num=0,force-raw=on", "-serial", "stdio", "-display", "none" },
};

// const currBoard = raspi3b;
const currBoard = qemuVirt;

// const env_path = "src/environments/statusControlTest";
// const env_path = "src/environments/basicMultiProcess";
// const env_path = "src/environments/basicMultithreading";
// const env_path = "src/environments/multiProcAndThreading";
// const env_path = "src/environments/sysCallTopicsTest";
// const env_path = "src/environments/sharedMemTopicsTest";
const env_path = "src/environments/basicKernelFunctionalityTest";
// const env_path = "src/environments/actionTest";

pub fn build(b: *std.Build) !void {
    // currBoard.config.checkConfig();
    const build_mode = std.builtin.Mode.ReleaseFast;
    const build_options = b.addOptions();

    // packages...
    // SOC builtin features
    var arm = ModuleDependency{ .name = try std.fmt.allocPrint(b.allocator, "arm", .{}), .module = b.createModule(.{ .source_file = .{ .path = "src/arm/arm.zig" } }) };
    // package for kernel interfaces such as the timer or the interrupt controller or general drivers
    var kpi = ModuleDependency{ .name = try std.fmt.allocPrint(b.allocator, "kpi", .{}), .module = b.createModule(.{ .source_file = .{ .path = "src/kpi/kpi.zig" } }) };
    // functions generally required
    var utils = ModuleDependency{ .name = try std.fmt.allocPrint(b.allocator, "utils", .{}), .module = b.createModule(.{ .source_file = .{ .path = "src/utils/utils.zig" } }) };
    // board pkg contains the configuration "template"(boardConfig.zig) and different configuration files for different boards
    var board = ModuleDependency{ .name = try std.fmt.allocPrint(b.allocator, "board", .{}), .module = b.createModule(.{ .source_file = .{ .path = "src/boards/" ++ currBoard.boardName ++ ".zig" } }) };
    var environment = ModuleDependency{ .name = try std.fmt.allocPrint(b.allocator, "environment", .{}), .module = b.createModule(.{ .source_file = .{ .path = env_path ++ "/envConfig.zig" } }) };
    // peripheral drivers
    var periph = ModuleDependency{ .name = try std.fmt.allocPrint(b.allocator, "periph", .{}), .module = b.createModule(.{ .source_file = .{ .path = "src/periph/periph.zig" } }) };
    // services that need to be accessed by kernel and other instances. the kernel allocator e.g.
    var sharedKernelServices = ModuleDependency{ .name = try std.fmt.allocPrint(b.allocator, "sharedKernelServices", .{}), .module = b.createModule(.{ .source_file = .{ .path = "src/kernel/sharedKernelServices/sharedKernelServices.zig" } }) };
    // package for all applications to call syscall
    var appLib = ModuleDependency{ .name = try std.fmt.allocPrint(b.allocator, "appLib", .{}), .module = b.createModule(.{ .source_file = .{ .path = "src/appLib/appLib.zig" } }) };

    const configTemplates = ModuleDependency{ .name = try std.fmt.allocPrint(b.allocator, "configTemplates", .{}), .module = b.createModule(.{ .source_file = .{ .path = "src/configTemplates/configTemplates.zig" } }) };

    //kernel threads
    var kernelThreads = ModuleDependency{ .name = try std.fmt.allocPrint(b.allocator, "kernelThreads", .{}), .module = b.createModule(.{ .source_file = .{ .path = env_path ++ "/kernelThreads/threads.zig" } }) };
    var setupRoutines = ModuleDependency{ .name = try std.fmt.allocPrint(b.allocator, "setupRoutines", .{}), .module = b.createModule(.{ .source_file = .{ .path = env_path ++ "/setupRoutines/routines.zig" } }) };

    // driver packages
    var interruptControllerDriver = ModuleDependency{ .name = try std.fmt.allocPrint(b.allocator, "interruptControllerDriver", .{}), .module = b.createModule(.{ .source_file = .{ .path = "src/boards/drivers/interruptController/interruptController.zig" } }) };
    var timerDriver = ModuleDependency{ .name = try std.fmt.allocPrint(b.allocator, "timerDriver", .{}), .module = b.createModule(.{ .source_file = .{ .path = "src/boards/drivers/timer/timer.zig" } }) };

    var sharedServices = ModuleDependency{ .name = try std.fmt.allocPrint(b.allocator, "sharedServices", .{}), .module = b.createModule(.{ .source_file = .{ .path = "src/sharedServices/sharedServices.zig" } }) };

    // inter package dependencies
    const kernelThreads_deps = [_]ModuleDependency{ board, arm, sharedKernelServices, periph };
    kernelThreads.module.dependencies = moduleDependenciesToArrayHashMap(b.allocator, &kernelThreads_deps);

    const setupRoutines_deps = [_]ModuleDependency{ board, arm, sharedKernelServices, periph };
    setupRoutines.module.dependencies = moduleDependenciesToArrayHashMap(b.allocator, &setupRoutines_deps);

    const kpi_deps = [_]ModuleDependency{ sharedKernelServices, arm };
    kpi.module.dependencies = moduleDependenciesToArrayHashMap(b.allocator, &kpi_deps);

    const interruptControllerDriver_deps = &[_]ModuleDependency{ board, arm };
    interruptControllerDriver.module.dependencies = moduleDependenciesToArrayHashMap(b.allocator, interruptControllerDriver_deps);

    const timerDriver_deps = [_]ModuleDependency{ board, utils, periph };
    timerDriver.module.dependencies = moduleDependenciesToArrayHashMap(b.allocator, &timerDriver_deps);

    const board_deps = [_]ModuleDependency{ kpi, utils, arm, interruptControllerDriver, timerDriver, configTemplates };
    board.module.dependencies = moduleDependenciesToArrayHashMap(b.allocator, &board_deps);

    const environment_deps = [_]ModuleDependency{configTemplates};
    environment.module.dependencies = moduleDependenciesToArrayHashMap(b.allocator, &environment_deps);

    const sharedServices_deps = [_]ModuleDependency{ board, appLib, environment };
    sharedServices.module.dependencies = moduleDependenciesToArrayHashMap(b.allocator, &sharedServices_deps);

    const sharedKernelServices_deps = [_]ModuleDependency{ board, environment, appLib, arm, utils, sharedServices, periph };
    sharedKernelServices.module.dependencies = moduleDependenciesToArrayHashMap(b.allocator, &sharedKernelServices_deps);

    const periph_deps = [_]ModuleDependency{board};
    periph.module.dependencies = moduleDependenciesToArrayHashMap(b.allocator, &periph_deps);

    const utils_deps = [_]ModuleDependency{ board, arm };
    utils.module.dependencies = moduleDependenciesToArrayHashMap(b.allocator, &utils_deps);

    const arm_deps = [_]ModuleDependency{ periph, utils, board, sharedKernelServices };
    arm.module.dependencies = moduleDependenciesToArrayHashMap(b.allocator, &arm_deps);

    const appLib_deps = [_]ModuleDependency{ board, utils, environment, sharedServices, sharedKernelServices };
    appLib.module.dependencies = moduleDependenciesToArrayHashMap(b.allocator, &appLib_deps);

    const temp_kernel_ld = "zig-cache/tmp/tempKernelLinker.ld";
    const temp_bl_ld = "zig-cache/tmp/tempBlLinker.ld";

    // compilation steps
    const update_linker_scripts_bl = UpdateLinkerScripts.create(b, .bootloader, temp_bl_ld, temp_kernel_ld, currBoard);
    const update_linker_scripts_k = UpdateLinkerScripts.create(b, .kernel, temp_bl_ld, temp_kernel_ld, currBoard);
    const scan_for_apps = ScanForApps.create(b, build_options);

    const build_and_run = b.step("qemu", "emulate the kernel with no graphics and output uart to console");
    const build_kernel_and_bootloader = b.step("kernel_and_bootloader", "building the kernel and the bootloader(which embedds the kernel)");
    // const launch_with_gdb = b.option(bool, "gdb", "Launch qemu with -s -S to allow for net gdb debugging") orelse false;

    // ------- apps/ actions
    const apps_and_action_step = try setEnvironment(b, build_mode, env_path, [4]ModuleDependency{ periph, board, configTemplates, appLib });

    // ------- kernel
    const kernel_exe = b.addExecutable(.{
        .name = "kernel",
        .target = .{ .cpu_arch = std.Target.Cpu.Arch.aarch64, .os_tag = std.Target.Os.Tag.freestanding, .abi = std.Target.Abi.eabihf },
        .optimize = build_mode,
    });
    kernel_exe.force_pic = false;
    kernel_exe.pie = false;
    kernel_exe.code_model = .large;
    kernel_exe.strip = false;

    kernel_exe.addModule(arm.name, arm.module);
    kernel_exe.addModule(sharedKernelServices.name, sharedKernelServices.module);
    kernel_exe.addModule(appLib.name, appLib.module);
    kernel_exe.addModule(sharedServices.name, sharedServices.module);
    kernel_exe.addModule(utils.name, utils.module);
    kernel_exe.addModule(kpi.name, kpi.module);
    kernel_exe.addModule(board.name, board.module);
    kernel_exe.addModule(environment.name, environment.module);
    kernel_exe.addModule(periph.name, periph.module);
    kernel_exe.addModule(interruptControllerDriver.name, interruptControllerDriver.module);
    kernel_exe.addModule(timerDriver.name, timerDriver.module);

    kernel_exe.addModule(kernelThreads.name, kernelThreads.module);
    kernel_exe.addModule(setupRoutines.name, setupRoutines.module);

    kernel_exe.addOptions("build_options", build_options);
    kernel_exe.setLinkerScriptPath(.{ .path = temp_kernel_ld });
    kernel_exe.addObjectFile(.{ .path = "src/kernel/kernel.zig" });
    kernel_exe.addCSourceFile(.{ .file = .{ .path = "src/kernel/exc_vec.S" }, .flags = undefined });

    kernel_exe.step.dependOn(&update_linker_scripts_k.step);
    kernel_exe.step.dependOn(&scan_for_apps.step);
    kernel_exe.step.dependOn(apps_and_action_step);

    const install_kernel_raw = kernel_exe.addObjCopy(.{ .format = .bin });
    const install_kernel_bin = b.addInstallBinFile(install_kernel_raw.getOutput(), "../../src/bootloader/bins/kernel.bin");
    install_kernel_raw.step.dependOn(&kernel_exe.step);
    install_kernel_bin.step.dependOn(&install_kernel_raw.step);

    // ------- bootloader
    const bl_exe = b.addExecutable(.{
        .name = "bootloader",
        .target = .{ .cpu_arch = std.Target.Cpu.Arch.aarch64, .os_tag = std.Target.Os.Tag.freestanding, .abi = std.Target.Abi.eabihf },
        .optimize = build_mode,
    });
    bl_exe.force_pic = false;
    bl_exe.pie = false;
    bl_exe.code_model = .large;
    bl_exe.addModule(arm.name, arm.module);
    bl_exe.addModule(utils.name, utils.module);
    bl_exe.addModule(board.name, board.module);
    bl_exe.addModule(periph.name, periph.module);
    bl_exe.addOptions("build_options", build_options);
    bl_exe.setLinkerScriptPath(std.build.FileSource{ .path = temp_bl_ld });
    bl_exe.addObjectFile(.{ .path = "src/bootloader/bootloader.zig" });
    bl_exe.addCSourceFile(.{ .file = .{ .path = "src/boards/drivers/bootInit/" ++ currBoard.boardName ++ "_boot.S" }, .flags = undefined });
    bl_exe.addCSourceFile(.{ .file = .{ .path = "src/bootloader/exc_vec.S" }, .flags = undefined });

    bl_exe.step.dependOn(&update_linker_scripts_bl.step);

    const install_bl_raw = bl_exe.addObjCopy(.{ .format = .bin });
    const install_bl_bin = b.addInstallBinFile(install_kernel_raw.getOutput(), "bootloader.bin");
    bl_exe.step.dependOn(&install_kernel_bin.step);
    install_bl_raw.step.dependOn(&bl_exe.step);
    install_bl_bin.step.dependOn(&install_bl_raw.step);

    // ------- BUILD/ QEMU
    build_kernel_and_bootloader.dependOn(&install_bl_bin.step);

    const qemu_launch_cmd = b.addSystemCommand(currBoard.qemu_launch_command);
    qemu_launch_cmd.step.dependOn(&install_bl_bin.step);
    build_and_run.dependOn(&qemu_launch_cmd.step);
}

fn setEnvironment(b: *std.Build, build_mode: std.builtin.Mode, comptime path: []const u8, app_deps: [4]ModuleDependency) !*std.Build.Step {
    const user_apps_path = path ++ "/userApps/";
    var dir = try std.fs.cwd().openIterableDir(user_apps_path, .{});
    var it = dir.iterate();
    const apps_action_step = b.step("apps_actions", "compiles apps and actions");
    while (try it.next()) |folder| {
        if (folder.kind != .directory or folder.name[0] == '_' or std.mem.eql(u8, folder.name, "actions")) continue;
        const app = try addApp(b, build_mode, try std.fmt.allocPrint(b.allocator, "{s}/{s}", .{ user_apps_path, folder.name }), app_deps);

        const install_app_raw = app.addObjCopy(.{ .format = .bin });
        const install_app_bin = b.addInstallBinFile(install_app_raw.getOutput(), try std.fmt.allocPrint(b.allocator, "../../src/kernel/bins/actions/{s}", .{folder.name}));

        install_app_raw.step.dependOn(&app.step);
        install_app_bin.step.dependOn(&install_app_raw.step);

        apps_action_step.dependOn(&install_app_bin.step);
    }
    const actions_path = path ++ "/userApps/actions/";
    dir = try std.fs.cwd().openIterableDir(actions_path, .{});
    it = dir.iterate();
    while (try it.next()) |folder| {
        if (folder.kind != .directory or folder.name[0] == '_' or std.mem.eql(u8, folder.name, "actions")) continue;
        const action = try addApp(b, build_mode, try std.fmt.allocPrint(b.allocator, "{s}/{s}", .{ actions_path, folder.name }), app_deps);
        const install_action_raw = action.addObjCopy(.{ .format = .bin });
        const install_action_bin = b.addInstallBinFile(install_action_raw.getOutput(), try std.fmt.allocPrint(b.allocator, "../../src/kernel/bins/apps/{s}", .{folder.name}));

        install_action_raw.step.dependOn(&action.step);
        install_action_bin.step.dependOn(&install_action_raw.step);

        apps_action_step.dependOn(&install_action_bin.step);
    }
    return apps_action_step;
}

fn addApp(b: *std.Build, build_mode: std.builtin.Mode, path: []const u8, app_deps: [4]ModuleDependency) !*std.Build.Step.Compile {
    const app = b.addExecutable(.{
        .name = std.fs.path.basename(path),
        .target = .{ .cpu_arch = std.Target.Cpu.Arch.aarch64, .os_tag = std.Target.Os.Tag.freestanding, .abi = std.Target.Abi.eabihf },
        .optimize = build_mode,
    });
    app.force_pic = false;
    app.pie = false;
    app.setLinkerScriptPath(std.build.FileSource{ .path = try std.fmt.allocPrint(b.allocator, "{s}/linker.ld", .{path}) });
    app.addObjectFile(.{ .path = try std.fmt.allocPrint(b.allocator, "{s}/main.zig", .{path}) });
    for (app_deps) |dep| app.addModule(dep.name, dep.module);
    // app.step.dependOn(&b.addInstallArtifact(app, .{}).step);
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

    pub fn create(b: *std.Build, to_update: ToUpdate, temp_bl_ld: []const u8, temp_kernel_ld: []const u8, board_config: BoardBuildConf) *UpdateLinkerScripts {
        const self = b.allocator.create(UpdateLinkerScripts) catch unreachable;
        self.* = .{
            .step = std.build.Step.init(.{ .id = .custom, .name = "UpdateLinkerScript", .owner = b, .makeFn = UpdateLinkerScripts.doStep }),
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
            for (line, 0..) |c, i| {
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

    fn doStep(step: *std.build.Step, prog_node: *std.Progress.Node) !void {
        _ = prog_node;
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

const ScanForApps = struct {
    step: std.build.Step,
    builder: *std.Build,
    build_options: *std.build.OptionsStep,

    pub fn create(b: *std.Build, build_options: *std.build.OptionsStep) *ScanForApps {
        const self = b.allocator.create(ScanForApps) catch unreachable;
        self.* = .{ .step = std.build.Step.init(.{ .id = .custom, .name = "ScanForApps", .owner = b, .makeFn = ScanForApps.doStep }), .builder = b, .build_options = build_options };
        return self;
    }

    fn doStep(step: *std.build.Step, prog_node: *std.Progress.Node) !void {
        _ = prog_node;
        const self = @fieldParentPtr(ScanForApps, "step", step);
        // searching for apps in apps/
        {
            var apps = std.ArrayList([]const u8).init(self.builder.allocator);
            var actions = std.ArrayList([]const u8).init(self.builder.allocator);
            defer actions.deinit();
            defer apps.deinit();

            var dir = std.fs.cwd().openIterableDir("zig-out/bin/apps/", .{}) catch |e| {
                if (e == error.FileNotFound) {
                    self.build_options.addOption([]const []const u8, "apps", &.{});
                    return;
                } else return e;
            };
            var it = dir.iterate();
            while (try it.next()) |file| {
                if (file.kind != .file) continue;
                try apps.append(file.name);
            }
            self.build_options.addOption([]const []const u8, "apps", apps.items);

            dir = std.fs.cwd().openIterableDir("zig-out/bin/actions/", .{}) catch |e| {
                if (e == error.FileNotFound) {
                    self.build_options.addOption([]const []const u8, "actions", &.{});
                    return;
                } else return e;
            };
            it = dir.iterate();
            while (try it.next()) |file| {
                if (file.kind != .file) continue;
                try actions.append(file.name);
            }
            self.build_options.addOption([]const []const u8, "actions", actions.items);
        }
    }
};

// std zig build additions

fn moduleDependenciesToArrayHashMap(arena: std.mem.Allocator, deps: []const ModuleDependency) std.StringArrayHashMap(*Module) {
    var result = std.StringArrayHashMap(*Module).init(arena);
    for (deps) |dep| {
        result.put(dep.name, dep.module) catch @panic("OOM");
    }
    return result;
}
