const regs = @import("rp2040.zig").registers;

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

/// List of critical peripherals that should not be reset at boot.
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

/// Sets bits for the specified peripherals. By setting
/// `config.invert_input` to true, the bits for all peripherals except for the
/// specified ones will be set.
/// Setting a bit will reset the peripheral, thus disabling it.
pub fn set(comptime peripherals: []const Peripheral, comptime config: Config) void {
    const mask = blk: {
        const m = generateMask(peripherals);
        const out = if (config.invert_input) ~m else m;
        break :blk out;
    };

    regs.RESETS.RESET.raw |= mask;
}

/// Clears bits for the specified peripherals. By setting `convert.invert_input`
/// to true, the bits for all peripherals except for the specified ones will be
/// cleared.
/// Clearing a bit will enable the peripheral.
///
/// By setting `config.wait_till_finished` the function will hang until enabling
/// of the specified peripherals is finished.
pub fn clear(comptime peripherals: []const Peripheral, comptime config: Config) void {
    const mask = blk: {
        const m = generateMask(peripherals);
        const out = if (config.invert_input) ~m else m;
        break :blk out;
    };

    regs.RESETS.RESET.raw &= ~mask;

    if (config.wait_till_finished) {
        while (regs.RESETS.RESET_DONE.raw & mask != mask) {}
    }
}

/// Generate a bitmask from a list of peripherals
inline fn generateMask(comptime peripherals: []const Peripheral) u32 {
    comptime var mask: u32 = 0;
    inline for (peripherals) |peripheral| {
        mask |= @as(u32, 1) << @enumToInt(peripheral);
    }
    return mask;
}
