const pico = @import("pico.zig");
const mmio = @import("mmio.zig");

const Peripheral = enum {
    adc,
    busctrl,
    dma,
    i2c0,
    i2c1,
    io_bank0,
    io_qspi,
    jtag,
    pads_bank0,
    pads_qspi,
    pio0,
    pio1,
    pll_sys,
    pll_usb,
    pwm,
    rtc,
    spi0,
    spi1,
    syscfg,
    sysinfo,
    tbman,
    timer,
    uart0,
    uart1,
    usbctrl,
};

pub const critical_blocks = [_]Peripheral{
    .io_qspi,
    .pads_qspi,
    .pll_usb,
    .usbctrl,
    .syscfg,
    .pll_sys,
};

const Config = struct {
    invert_input: bool = false,
    wait_till_finished: bool = false,
};

pub fn set(comptime blocks: []const Peripheral, comptime config: Config) void {
    const mask = blk: {
        const m = generateMask(blocks);
        const out = if (config.invert_input) ~m else m;
        break :blk out;
    };

    Regs.reset.set(mask);
}

pub fn clear(comptime blocks: []const Peripheral, comptime config: Config) void {
    const mask = blk: {
        const m = generateMask(blocks);
        const out = if (config.invert_input) ~m else m;
        break :blk out;
    };

    Regs.reset.clear(mask);

    if (config.wait_till_finished) {
        while (Regs.reset_done.read() & mask != mask) {}
    }
}

inline fn generateMask(comptime blocks: []const Peripheral) u32 {
    comptime var mask: u32 = 0;
    inline for (blocks) |block| {
        mask |= @as(u32, 1) << @enumToInt(block);
    }
    return mask;
}

//
// Registers
//
const Regs = struct {
    const reset = mmio.Reg32.init(pico.RESETS_BASE);
    const wdsel = mmio.Reg32.init(pico.RESETS_BASE + pico.RESETS_WDSEL_OFFSET);
    const reset_done = mmio.Reg32.init(pico.RESETS_BASE + pico.RESETS_RESET_DONE_OFFSET);
};
