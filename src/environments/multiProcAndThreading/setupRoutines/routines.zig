const board = @import("board");
const sharedKernelServices = @import("sharedKernelServices");
const Scheduler = sharedKernelServices.Scheduler;

const bcm2835Setup = @import("raspi3bSetup.zig").bcm2835Setup;
const qemuVirtSetup = @import("qemuVirtSetup.zig").qemuVirtSetup;



const boardSpecificSetup = blk: {

    switch (board.config.board) {
    	.raspi3b => {
			break :blk [_]fn (scheduler: *Scheduler) void{ bcm2835Setup };
    	},
    	.qemuVirt => {
			break :blk [_]fn (scheduler: *Scheduler) void{ qemuVirtSetup };	
    	}
	}

};

// setupRoutines array is loaded and inited by the kernel 
pub const setupRoutines = [_]fn (scheduler: *Scheduler) void{  } ++ boardSpecificSetup;
