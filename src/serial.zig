const utils = @import("utils.zig");
const adr = @import("raspberryAddr.zig");

const KprintfParsingState = enum { filling_val, printing_ch };

pub const KprintfErr = error{
    TypeNotFound,
    TypeMissMatch,
    UnusedArgs,
    NotEnoughArgs,
};

fn putChar(ch: u8) void {
    adr.mmio_uart.* = ch;
}

fn print(print_string: []const u8) void {
    for (print_string) |ch| {
        putChar(ch);
    }
}

pub fn kprint(comptime print_string: []const u8, args: anytype) void {
    comptime var print_state = KprintfParsingState.printing_ch;
    comptime var i_args_parsed: u8 = 0;
    // inline required bc not rolled out loop wouldn't mut printing_ch
    inline for (print_string) |ch, i| {
        switch (ch) {
            else => {
                if (print_state == KprintfParsingState.printing_ch) {
                    putChar(ch);
                }
            },
            '{' => {
                print_state = KprintfParsingState.filling_val;
                switch (print_string[i + 1]) {
                    'u' => {
                        if (print_string[i + 2] != '}') {
                            @panic(KprintfErr.TypeNotFound);
                        }
                        if (i_args_parsed >= args.len) {
                            @panic(KprintfErr.NotEnoughArgs);
                        }
                        kprintUi(args[i_args_parsed], utils.PrintStyle.string);
                        i_args_parsed += 1;
                    },
                    's' => {
                        if (print_string[i + 2] != '}') {
                            @panic(KprintfErr.TypeNotFound);
                        }
                        if (i_args_parsed >= args.len) {
                            @panic(KprintfErr.NotEnoughArgs);
                        }
                        print(args[i_args_parsed]);
                        i_args_parsed += 1;
                    },
                    else => {
                        @panic(KprintfErr.TypeNotFound);
                    },
                }
            },
            '}' => {
                print_state = KprintfParsingState.printing_ch;
            },
            0 => break,
        }
    }
    if (i_args_parsed != args.len) {
        @panic(KprintfErr.UnusedArgs);
    }
}

// pub fn kprint_ui(num: u64, print_style: utils.PrintStyle) void {
//     var ret = utils.uitoa(num, print_style);
//     var j: usize = 0;
//     while (j < ret.len) : (j += 1) {
//         put_char(ret.arr[j]);
//     }
// }

// -- cannot use existing functions(commented fn above) because of Zig Aarch64 issue described here https://github.com/ziglang/zig/issues/11859
fn kprintUi(num: u64, print_style: utils.PrintStyle) void {
    var str = [_]u8{0} ** 20;

    if (num == 0) {
        str[0] = 0;
        return;
    }

    var rem: u64 = 0;
    var i: u8 = 0;
    var num_i = num;
    while (num_i != 0) {
        rem = @mod(num_i, @enumToInt(print_style));
        if (rem > 9) {
            str[i] = @truncate(u8, (rem - 10) + 'a');
        } else {
            str[i] = @truncate(u8, rem + '0');
        }
        i += 1;

        num_i = num_i / @enumToInt(print_style);
    }
    utils.reverseString(&str, i);

    var j: usize = 0;
    while (j < i) : (j += 1) {
        putChar(str[j]);
    }
}
