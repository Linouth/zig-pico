const resets = @import("resets.zig");

const regs = @import("rp2040.zig").registers;

const Pll = enum {
    sys,
    usb,
};

pub fn init(
    comptime pll: Pll,
    comptime refdiv: usize,
    comptime vco_freq: usize,
    comptime post_div1: usize,
    comptime post_div2: usize,
    comptime clock_mhz: usize,
) void {
    const r = switch (pll) {
        .sys => regs.PLL_SYS,
        .usb => regs.PLL_USB,
    };

    if (vco_freq < 400_000_000 or vco_freq > 1600_000_000)
        @compileError("PLL: vco_freq can only range from 400 to 1600MHz");

    if (post_div1 < 1 or post_div1 > 7 or post_div2 < 1 or post_div2 > 7)
        @compileError("PLL: post_divn can only range from 1 to 7");

    const ref_freq = clock_mhz * 1_000_000 / refdiv;
    const fbdiv = vco_freq / ref_freq;

    if (fbdiv < 16 or fbdiv > 320)
        @compileError("PLL: fbdiv can only range from 16 to 320");

    if ((ref_freq / refdiv) > (vco_freq / 16))
        @compileError("PLL: Input frequency (FREF/REFDIV) cannot be greater than vco_freq / 16");

    if ((ref_freq / refdiv) < 5_000_000)
        @compileError("PLL: Input frequency (FREF/REFDIV) cannot be smaller than 5 MHz");

    const foutpostdiv = vco_freq / (post_div1 * post_div2);
    switch (pll) {
        .sys => if (foutpostdiv > 133_000_000)
            @compileError("PLL: Invalid sys frequency. Max sys frequency is 133MHz."),
        .usb => if (foutpostdiv > 48_000_000)
            @compileError("PLL: Invalid usb frequency. Max usb frequency is 48MHz."),
    }

    // Reset PLL
    const reset_block = switch (pll) {
        .sys => .pll_sys,
        .usb => .pll_usb,
    };
    resets.set(&.{ reset_block }, .{});
    resets.clear(&.{ reset_block }, .{ .wait_till_finished = true });

    // Configure dividers
    r.CS.modify(.{
        .REFDIV = refdiv,
    });
    r.FBDIV_INT.raw = fbdiv;

    // Turn on PLL
    r.PWR.modify(.{
        .PD = 0,
        .VCOPD = 0,
    });

    // Wait till VCO has locked onto the requested frequency
    while (r.CS.read().LOCK != 1) {}

    // Configure post divider
    r.PRIM.modify(.{
        .POSTDIV1 = post_div1,
        .POSTDIV2 = post_div2,
    });

    // Turn on post divider
    r.PWR.modify(.{
        .POSTDIVPD = 0,
    });
}
