const mmio = @import("mmio.zig");
const pico = @import("pico.zig");
const resets = @import("resets.zig");

const Pll = enum {
    sys,
    usb,
};

pub fn init(
    comptime pll: Pll,
    comptime refdiv: usize,
    comptime vco_freq: usize,
    comptime post_div1: usize,
    comptime post_div2: usize
) void {
    const regs = switch (pll) {
        .sys => pll_sys,
        .usb => pll_usb,
    };

    if (vco_freq < 400_000_000 or vco_freq > 1600_000_000)
        @compileError("PLL: vco_freq can only range from 400 to 1600MHz");

    if (post_div1 < 1 or post_div1 > 7 or post_div2 < 1 or post_div2 > 7)
        @compileError("PLL: post_divn can only range from 1 to 7");

    const ref_freq = pico.XOSC_MHZ * 1_000_000 / refdiv;
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
    regs.cs.modify(.{
        .refdiv = refdiv,
    });
    regs.fbdiv_int.write(fbdiv);

    // Turn on PLL
    regs.pwr.modify(.{
        .pd = 0,
        .vcopd = 0,
    });

    // Wait till VCO has locked onto the requested frequency
    while (regs.cs.read().lock != 1) {}

    // Configure post divider
    regs.prim.modify(.{
        .postdiv1 = post_div1,
        .postdiv2 = post_div2,
    });

    // Turn on post divider
    regs.pwr.modify(.{
        .postdivpd = 0,
    });
}

//
// Registers
//

const PwrReg = packed struct {
    pd: u1,
    _reserved0: u1,
    dsmpd: u1,
    postdivpd: u1,
    _reserved1: u1,
    vcopd: u1,
    _reserved3: u26,
};

const CsReg = packed struct {
    refdiv: u6,
    _reserved0: u2,
    bypass: u1,
    _reserved1: u7,
    _reserved2: u15,
    lock : u1,
};

const PrimReg = packed struct {
    _reserved0: u12,
    postdiv2: u3,
    _reserved1: u1,
    postdiv1: u3,
    _reserved2: u13,
};

const pll_sys: mmio.RegisterList(pico.PLL_SYS_BASE, &.{
    .{ .name = "cs", .type = CsReg },
    .{ .name = "pwr", .type = PwrReg },
    .{ .name = "fbdiv_int", .type = u32 },
    .{ .name = "prim", .type = PrimReg },
}) = .{};

const pll_usb: mmio.RegisterList(pico.PLL_USB_BASE, &.{
    .{ .name = "cs", .type = CsReg },
    .{ .name = "pwr", .type = PwrReg },
    .{ .name = "fbdiv_int", .type = u32 },
    .{ .name = "prim", .type = PrimReg },
}) = .{};
