const board = @import("board");
const arm = @import("arm");

pub fn getTimerFreqInHertz() usize {
    // if the frequency is predefined, we can read it from the config
    if (board.config.timer_freq_in_hertz) |freq| return freq;

    // if board.config.timer_freq_in_hertz is null, the freq has to be read from the board
    switch (board.config.board) {
        .qemuVirt => {
            return arm.genericTimer.getFreq();
        },
    }
}
