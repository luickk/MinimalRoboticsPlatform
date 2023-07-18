const std = @import("std");
const env = @import("environment");
const KernelAlloc = @import("KernelAllocator.zig").KernelAllocator;
const StatusType = env.envConfTemplate.StatusType;

pub const StatusControl = struct {
    const GenericStatus = struct {
        status_type: StatusType,
        name: []const u8,
        id: u16,
        mem_addr: usize,
        size: usize,
    };
    const Error = error{
        NameNotFound,
        TypesNotMatching,
        WrongInterface,
    };
    // yes, thats the plural
    statuses: [env.env_config.countStatuses()]GenericStatus,
    mem_pool: []u8,

    pub fn init(kernel_alloc: *KernelAlloc) !StatusControl {
        var accumulatedBuffSize: usize = 0;
        var statuses = [_]GenericStatus{.{ .status_type = undefined, .name = undefined, .mem_addr = undefined, .size = undefined, .id = undefined }} ** env.env_config.countStatuses();
        var i: usize = 0;
        for (env.env_config.status_control) |*status_control_conf| {
            if (status_control_conf.status_type != .topic) {
                i += 1;
                switch (status_control_conf.status_type) {
                    .string => {
                        accumulatedBuffSize += @sizeOf([100]u8);
                        statuses[i] = GenericStatus{ .status_type = status_control_conf.status_type, .mem_addr = undefined, .size = @sizeOf([100]u8), .name = status_control_conf.name, .id = status_control_conf.id };
                    },
                    .usize, .isize => {
                        accumulatedBuffSize += @sizeOf(usize);
                        statuses[i] = GenericStatus{ .status_type = status_control_conf.status_type, .mem_addr = undefined, .size = @sizeOf(usize), .name = status_control_conf.name, .id = status_control_conf.id };
                    },
                    .bool => {
                        accumulatedBuffSize += @sizeOf(bool);
                        statuses[i] = GenericStatus{ .status_type = status_control_conf.status_type, .mem_addr = undefined, .size = @sizeOf(bool), .name = status_control_conf.name, .id = status_control_conf.id };
                    },
                    else => {},
                }
            }
        }
        const status_mem = try kernel_alloc.alloc(u8, accumulatedBuffSize, null);
        var used_status_mem: usize = 0;
        i = 0;
        for (env.env_config.status_control) |*status_control_conf| {
            if (status_control_conf.status_type != .topic) {
                const size = status_control_conf.status_type.statusTypeLen() orelse return Error.WrongInterface;
                i += 1;
                statuses[i].mem_addr = @ptrToInt(status_mem[used_status_mem .. used_status_mem + size].ptr);
                used_status_mem += size;
            }
        }
        return .{
            .statuses = statuses,
            .mem_pool = status_mem,
        };
    }

    pub fn updateStatus(self: *StatusControl, name: []const u8, value: anytype) !void {
        if (self.findStatusByName(name)) |index| {
            if (!self.statuses[index].status_type.isTypeEqual(@TypeOf(value))) return Error.TypesNotMatching;
            var value_as_bytes: []const u8 = undefined;
            value_as_bytes.ptr = @ptrCast([*]const u8, &value);
            value_as_bytes.len = @sizeOf(@TypeOf(value));
            std.mem.copy(u8, @intToPtr([]u8, self.statuses[index].mem_addr), value_as_bytes);
        }
    }

    pub fn updateStatusRaw(self: *StatusControl, id: u16, val_mem_addr: usize) !void {
        if (self.findStatusById(id)) |index| {
            @memcpy(@intToPtr([*]u8, self.statuses[index].mem_addr), @intToPtr([*]u8, val_mem_addr), self.statuses[index].size);
        } else return Error.NameNotFound;
    }

    pub fn readStatus(self: *StatusControl, comptime InpT: type, comptime name: []const u8) !InpT {
        const T: type = (try env.env_config.getStatusInfo(name)).type;
        if (self.findStatusByName(name)) |index| {
            return @intToPtr(*T, self.statuses[index].mem_addr).*;
        }
        return Error.NameNotFound;
    }

    pub fn readStatusRaw(self: *StatusControl, id: u16, ret_buff: usize) !void {
        if (self.findStatusById(id)) |index| {
            @memcpy(@intToPtr([*]u8, ret_buff), @intToPtr([*]u8, self.statuses[index].mem_addr), self.statuses[index].size);
        } else return Error.NameNotFound;
    }

    // returns index
    fn findStatusByName(self: *StatusControl, name: []const u8) ?usize {
        for (self.statuses) |*status, i| {
            if (std.mem.eql(u8, status.name, name)) return i;
        }
        return null;
    }

    // returns index
    fn findStatusById(self: *StatusControl, id: u16) ?usize {
        for (self.statuses) |*status, i| {
            if (status.id == id) return i;
        }
        return null;
    }
};
