
pub const BoardBuildConf = struct {
    boardName: []const u8,
    has_rom: bool,
    // the kernel is loaded by into 0x8000 ram by the gpu, so no relocation (or rom) required
    rom_start_addr: ?usize,
    bl_load_addr: ?usize,
    va_start: usize,
    qemu_launch_command: []const []const u8,
};