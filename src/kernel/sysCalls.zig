const periph = @import("periph");
const pl011 = periph.Pl011(.ttbr1);

const kprint = periph.uart.UartWriter(.ttbr1).kprint;
const arm = @import("arm");
const ProccessorRegMap = arm.processor.ProccessorRegMap;

// todo => add length..
pub fn sysCallPrint(data: [*]u8, len: usize) callconv(.C) void {
    kprint("pc: {x}\n", .{ProccessorRegMap.getPc()});
    kprint("CALLED ptr: {*} len: {d} \n", .{ data, len });
    var sliced_data: []u8 = undefined;
    sliced_data.len = len;
    sliced_data.ptr = data;
    pl011.write(sliced_data);
}
