const board = @import("board");
const arm = @import("arm");

var cachedFreq: ?usize = null;

pub fn getTimerFreqInHertz() usize {

    // if board.config.timer_freq_in_hertz is null, the freq has to be read from the board
    switch (board.config.board) {
        .qemuVirt => {
            if (cachedFreq == null) cachedFreq = arm.genericTimer.getFreq();
            return cachedFreq.?;
        },
        .raspi3b => {
            if (board.config.timer_freq_in_hertz) |freq| return freq;
        },
    }
}
