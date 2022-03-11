const xosc = @import("xosc.zig");
const pll = @import("pll.zig");

const regs = @import("rp2040.zig").registers;

const Clock = enum {
    gpout0,
    gpout1,
    gpout2,
    gpout3,
    ref,
    sys,
    peri,
    usb,
    adc,
    rtc,
};

// TODO: Add ability to set custom clock configurations
pub fn init(comptime clock_mhz: usize) void {
    // Disable resus for sys clock
    regs.CLOCKS.CLK_SYS_RESUS_CTRL.raw = 0;

    xosc.init(clock_mhz * 1_000_000 / 1000);

    // Switch both sys and ref away from aux clocks before touchting PLLs
    regs.CLOCKS.CLK_SYS_CTRL.modify(.{
        .SRC = 0,
    });
    while (regs.CLOCKS.CLK_SYS_SELECTED.* != 1) {}

    regs.CLOCKS.CLK_REF_CTRL.modify(.{
        .SRC = 0,
    });
    while (regs.CLOCKS.CLK_REF_SELECTED.* != 1) {}

    // The PLL configuration below is taken directly from the pico-sdk
    // Configure PLLs
    //                   REF     FBDIV VCO            POSTDIV
    // PLL SYS: 12 / 1 = 12MHz * 125 = 1500MHZ / 6 / 2 = 125MHz
    // PLL USB: 12 / 1 = 12MHz * 40  = 480 MHz / 5 / 2 =  48MHz
    pll.init(.sys, 1, 1500_000_000, 6, 2, clock_mhz);
    pll.init(.usb, 1, 480_000_000, 5, 2, clock_mhz);
    // TODO: Would be cool to have the functionality of the 'vcocalc.py' script
    // built into here as comptime.

    configure(.ref, .{
        .src = 0x2,
        .src_freq = clock_mhz * 1_000_000,
        .freq = clock_mhz * 1_000_000,
    });

    configure(.sys, .{
        .src = 0x1,    // aux
        .auxsrc = 0x0, // pll_sys
        .src_freq = 125_000_000,
        .freq = 125_000_000,
    });

    configure(.peri, .{
        .auxsrc = 0x0, // pll_sys
        .src_freq = 125_000_000,
        .freq = 125_000_000,
    });

    //configure(.usb, .{
    //    .auxsrc = 0x0, // pll_usb
    //    .src_freq = 48_000_000,
    //    .freq = 48_000_000,
    //});

    configure(.adc, .{
        .auxsrc = 0x0, // pll_usb
        .src_freq = 48_000_000,
        .freq = 48_000_000,
    });

    configure(.rtc, .{
        .auxsrc = 0x0, // pll_usb
        .src_freq = 48_000_000,
        .freq = 46875,
    });
}

const ClockConf = struct {
    src: ?u2 = null,
    auxsrc: ?u3 = null,
    src_freq: u32,
    freq: u32,
};

fn configure(comptime clock: Clock, comptime conf: ClockConf) void {
    if (conf.freq > conf.src_freq)
        @compileError("Desired frequency cannot be higher than the source frequency");

    if ((clock != .sys and clock != .ref) and (conf.src != null))
        @compileError("This clock does not have a glitchless src");

    // Div reg is a fixed-point number (24.8)
    const div: u32 = (@as(u64, conf.src_freq) << 8) / conf.freq;

    //const ctrl = @field(clock_regs, @tagName(clock) ++ "_ctrl");
    //const selected = @field(clock_regs, @tagName(clock) ++ "_selected");

    const clock_reg_prefixes = .{
        "CLK_GPOUT0",
        "CLK_GPOUT1",
        "CLK_GPOUT2",
        "CLK_GPOUT3",
        "CLK_REF",
        "CLK_SYS",
        "CLK_PERI",
        "CLK_USB",
        "CLK_ADC",
        "CLK_RTC",
    };

    const prefix = clock_reg_prefixes[@enumToInt(clock)];
    const ctrl = @field(regs.CLOCKS, prefix ++ "_CTRL");
    const selected = @field(regs.CLOCKS, prefix ++ "_SELECTED");

    // Disable clock, or set it to base glitchess clock
    switch (clock) {
        // Glitchless
        .ref, .sys => {
            ctrl.modify(.{
                .SRC = 0,
            });

            while (selected.* != 1) {}
        },

        // The rest
        else => {
            ctrl.modify(.{
                .ENABLE = 0,
            });

            // Wait for 3 cycles of the target clock speed for the clock to
            // propagate
            // TODO: This is hacky and hard-coded. The SDK keeps track of the
            // configured frequencies and delays for an actual 3 cycles of the
            // destination clock frequency.
            const cycles: u32 = (125_000_000 / 46875 * 3) / 3;
            asm volatile (
                \\1:
                \\subs r0, #1
                \\bne 1b
                :: [_] "{r0}" (cycles)
                : "r0");
        },
    }

    // Set aux src if specified
    if (conf.auxsrc) |auxsrc| {
        ctrl.modify(.{
            .AUXSRC = auxsrc,
        });
    }

    // Set glitchless src if specified, and wait till it has switched
    if (conf.src) |src| {
        ctrl.modify(.{
            .SRC = src,
        });

        while (selected.* != (@as(u32, 1) << src)) {}
    }

    // Enable clock again (only does something on aux clocks)
    switch (clock) {
        .ref, .sys => {},
        else => {
            ctrl.modify(.{
                .ENABLE = 1,
            });
        },
    }

    // Set divider
    @field(regs.CLOCKS, prefix ++ "_DIV").raw = div;
}
