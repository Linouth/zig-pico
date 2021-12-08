const pico = @import("pico.zig");
const sio = @import("sio.zig");
const mmio = @import("mmio.zig");
const nvic = @import("nvic.zig");

const CallbackFn = fn(pin: Gpio, triggers: Intr.TriggersBitfield) void;
var callback: ?CallbackFn = null;

pub const Gpio = struct {
    pin: u5,
    bank: *const BankRegs,

    const GpioConfig = struct {
        bank: Bank = .bank0,
        func: Function = .sio,

        mode: Mode = .input_output,
        pull: Pull = .pull_down,
        drive_current: Current = .current_4mA,
        slew_fast: bool = false,
        schmitt_trigger: bool = true,
    };

    const Bank = enum(u1) {
        bank0,
        qspi,
    };

    const Function = enum(u5) {
        xip,
        spi,
        uart,
        i2c,
        pwm,
        sio,
        pio0,
        pio1,
        clock,
        usb,
        none = 0x1f,
    };

    const Mode = enum(u2) {
        input,
        output,
        input_output,
        none,
    };

    const Pull = enum(u2) {
        pull_up,
        pull_down,
        float,
    };

    const Current = enum(u2) {
        current_2mA,
        current_4mA,
        current_8mA,
        current_12mA,
    };

    /// Create new GPIO instance for the specified pin.
    pub fn load(comptime pin: u5, comptime bank: Bank) Gpio {
        switch (bank) {
            .bank0 => if (pin >= pico.NUM_BANK0_GPIOS)
                @compileError("There are only 30 GPIOs in BANK0."),
            .qspi => if (pin >= pico.NUM_QSPI_GPIOS)
                @compileError("There are only 5 GPIOs in the QSPI bank."),
        }

        const bank_regs = switch (bank) {
            .bank0 => &bank0,
            .qspi => &qspi,
        };

        return Gpio {
            .pin = pin,
            .bank = bank_regs,
        };
    }

    /// Create new GPIO instance, and initialize the pin as specified in `config`
    pub fn init(comptime pin: u5, comptime config: GpioConfig) Gpio {
        const self = Gpio.load(pin, config.bank);

        // Clear and configure output
        self.clear();

        // TODO: Set the registers here directly in one go, instead of modifying
        // them bit by bit (read full, modify bit, write full, repeat...)
        self.setMode(config.mode);
        self.setPull(config.pull);
        self.setDriveCurrent(config.drive_current);
        self.enableSchmitt(config.schmitt_trigger);
        self.enableSlew(config.slew_fast);

        // Set gpio function
        self.bank.ctrl[self.pin].write(@enumToInt(config.func));

        return self;
    }

    /// Configure internals for the specified mode (input, output, both)
    fn setMode(self: Gpio, mode: Mode) void {
        switch (mode) {
            .input => {
                self.bank.pads[self.pin].modify(.{
                    .input_enable = 1,
                    .output_disable = 1,
                });
                self.bank.sio.oe_clr.write(@as(u32, 1) << self.pin);
            },
            .output => {
                self.bank.pads[self.pin].modify(.{
                    .input_enable = 0,
                    .output_disable = 0,
                });
                self.bank.sio.oe_set.write(@as(u32, 1) << self.pin);
            },
            .input_output => {
                self.bank.pads[self.pin].modify(.{
                    .input_enable = 1,
                    .output_disable = 0,
                });
                self.bank.sio.oe_set.write(@as(u32, 1) << self.pin);
            },
            .none => {
                self.bank.pads[self.pin].modify(.{
                    .input_enable = 0,
                    .output_disable = 1,
                });
                self.bank.sio.oe_clr.write(@as(u32, 1) << self.pin);
            },
        }
    }

    fn getMode(self: Gpio) Mode {
        const reg = self.bank.pads[self.pin].read();

        if (reg.input_enable == 1 and reg.output_disable == 1) {
            return .input;
        } else if (reg.input_enable == 1 and reg.output_disable == 0) {
            return .input_output;
        } else if (reg.input_enable == 0 and reg.output_disable == 0) {
            return .output;
        } else {
            return .none;
        }
    }

    /// Enable internal pull-up/-down resistors
    fn setPull(self: Gpio, pull: Pull) void {
        switch (pull) {
            .pull_up => {
                self.bank.pads[self.pin].modify(.{
                    .pull_up = 1,
                    .pull_down = 0,
                });
            },
            .pull_down => {
                self.bank.pads[self.pin].modify(.{
                    .pull_up = 0,
                    .pull_down = 1,
                });
            },
            .float => {
                self.bank.pads[self.pin].modify(.{
                    .pull_up = 0,
                    .pull_down = 0,
                });
            },
        }
    }

    /// Set the maximum output drive current
    fn setDriveCurrent(self: Gpio, current: Current) void {
        self.bank.pads[self.pin].modify(.{
            .drive_current = current,
        });
    }

    /// Enable/disable fast slewrate
    fn enableSlew(self: Gpio, slew: bool) void {
        self.bank.pads[self.pin].modify(.{
            .slew_fast = @boolToInt(slew),
        });
    }

    /// Enable/disable schmitt trigger (input hysteresis)
    fn enableSchmitt(self: Gpio, schmitt: bool) void {
        self.bank.pads[self.pin].modify(.{
            .schmitt_trigger = @boolToInt(schmitt),
        });
    }

    pub inline fn set(self: Gpio) void {
        self.bank.sio.set.write(@as(u32, 1) << self.pin);
    }

    pub inline fn clear(self: Gpio) void {
        self.bank.sio.clr.write(@as(u32, 1) << self.pin);
    }

    pub inline fn toggle(self: Gpio) void {
        self.bank.sio.xor.write(@as(u32, 1) << self.pin);
    }

    // TODO: Redo interrupt system. 'trig' should be a bitfield
    pub fn irqEnable(self: Gpio, target: Intr.Target, trig: Intr.Trigger) void {
        // Clear pending interrupts
        nvic.clearIrq(.io_irq_bank0);
        nvic.clearIrq(.io_irq_qspi);
        self.irqAcknowledge();

        const inte = switch(target) {
            .proc0 => self.bank.proc0_inte,
            .proc1 => self.bank.proc1_inte,
            .dormant_wake => self.bank.dormant_wake_inte,
        };

        // TODO: Switch to trigger bitfield
        const mask = @as(u32, 1) << ((self.pin % 8) * 4 + @enumToInt(trig));
        inte[self.pin/8].set(mask);
    }

    pub fn irqAcknowledge(self: Gpio) void {
        {
            const intr = self.bank.intr[self.pin / 8];
            intr.write(@as(u32, 0xf) << 4 * (self.pin % 8));
        }

        // TODO: Think of a better solution for this
        {
            const intf = self.bank.proc0_intf[self.pin / 8];
            intf.clear(@as(u32, 0xf) << 4 * (self.pin%8));
        }

        {
            const intf = self.bank.proc1_intf[self.pin / 8];
            intf.clear(@as(u32, 0xf) << 4 * (self.pin%8));
        }

        {
            const intf = self.bank.dormant_wake_intf[self.pin / 8];
            intf.clear(@as(u32, 0xf) << 4 * (self.pin%8));
        }
    }
};

pub fn setHandler(handler: CallbackFn) void {
    if (callback == null) {
        nvic.enableIrq(.io_irq_bank0, 0, bank0IrqHandler);
        nvic.enableIrq(.io_irq_qspi, 0, qspiIrqHandler);
    }
    callback = handler;
}

inline fn irqHelper(bank: Gpio.Bank) void {
    const target = @intToEnum(Intr.Target, sio.getCoreNum());

    const pin_count = switch (bank) {
        .bank0 => pico.NUM_BANK0_GPIOS,
        .qspi => pico.NUM_BANK0_GPIOS,
    };

    var pin: u5 = 0;
    while (pin < pin_count) : (pin += 1) {
        const ints = switch (target) {
            .proc0 => bank0.proc0_ints,
            .proc1 => bank0.proc1_ints,
            .dormant_wake => unreachable,
        };

        const triggers = @truncate(u4, bank0.proc0_ints[pin/8].read() >> (4 * (pin%8)));

        if (triggers == 0)
            continue;

        // Create new Gpio at runtime (cannot use 'load' here)
        const gpio = Gpio {
            .pin = pin,
            .bank = switch (bank) {
                .bank0 => &bank0,
                .qspi => &qspi,
            },
        };

        gpio.irqAcknowledge();

        if (callback) |cb| {
            // TODO: Convert 'triggers' to useful type
            cb(gpio, @bitCast(Intr.TriggersBitfield, triggers));
        }
    }
}

pub fn bank0IrqHandler() void {
    irqHelper(.bank0);
}

pub fn qspiIrqHandler() void {
    irqHelper(.qspi);
}

//
// Registers
//

const BankRegs = struct {
    status: []const mmio.Reg(u32),
    ctrl: []const mmio.Reg(u32),
    pads: []const mmio.Reg(PadReg),

    intr: [] const mmio.Reg(u32),
    proc0_inte: [] const mmio.Reg(u32),
    proc0_intf: [] const mmio.Reg(u32),
    proc0_ints: [] const mmio.Reg(u32),
    proc1_inte: [] const mmio.Reg(u32),
    proc1_intf: [] const mmio.Reg(u32),
    proc1_ints: [] const mmio.Reg(u32),
    dormant_wake_inte: [] const mmio.Reg(u32),
    dormant_wake_intf: [] const mmio.Reg(u32),
    dormant_wake_ints: [] const mmio.Reg(u32),

    sio: struct {
        in: mmio.Reg32,

        out: mmio.Reg32,
        set: mmio.Reg32,
        clr: mmio.Reg32,
        xor: mmio.Reg32,

        oe: mmio.Reg32,
        oe_set: mmio.Reg32,
        oe_clr: mmio.Reg32,
        oe_xor: mmio.Reg32
    },
};

const PadReg = packed struct {
    slew_fast: u1,
    schmitt_trigger: u1,
    pull_down: u1,
    pull_up: u1,
    drive_current: Gpio.Current,
    input_enable: u1,
    output_disable: u1,

    // BUG: Somehow going from u16 to u17 adds two bytes instead of one in size.
    // Adding a separate field with a single byte (or less) does correctly
    // increase the size with just one byte.
    _reserved0: u16,
    _reserved1: u8,
};

// TODO: Get rid of this Intr struct
pub const Intr = packed struct {
    const Target = enum {
        proc0,
        proc1,
        dormant_wake,
    };

    const Trigger = enum {
        level_low,
        level_high,
        edge_low,
        edge_high,
    };

    pub const TriggersBitfield = packed struct {
        level_low: bool,
        level_high: bool,
        edge_low: bool,
        edge_high: bool,
    };
};

const bank0 = BankRegs {
    .status = &mmio.Reg(u32).initMultiple(pico.IO_BANK0_BASE, pico.NUM_BANK0_GPIOS, 8),
    .ctrl = &mmio.Reg(u32).initMultiple(pico.IO_BANK0_BASE + 4, pico.NUM_BANK0_GPIOS, 8),
    .pads = &mmio.Reg(PadReg).initMultiple(
        pico.PADS_BANK0_BASE + pico.PADS_BANK0_GPIO0_OFFSET, pico.NUM_BANK0_GPIOS, 4),

    .intr = &mmio.Reg(u32).initMultiple(pico.IO_BANK0_BASE + pico.IO_BANK0_INTR0_OFFSET, 4, 4),
    .proc0_inte = &mmio.Reg(u32).initMultiple(pico.IO_BANK0_BASE + pico.IO_BANK0_PROC0_INTE0_OFFSET, 4, 4),
    .proc0_intf = &mmio.Reg(u32).initMultiple(pico.IO_BANK0_BASE + pico.IO_BANK0_PROC0_INTF0_OFFSET, 4, 4),
    .proc0_ints = &mmio.Reg(u32).initMultiple(pico.IO_BANK0_BASE + pico.IO_BANK0_PROC0_INTS0_OFFSET, 4, 4),
    .proc1_inte = &mmio.Reg(u32).initMultiple(pico.IO_BANK0_BASE + pico.IO_BANK0_PROC1_INTE0_OFFSET, 4, 4),
    .proc1_intf = &mmio.Reg(u32).initMultiple(pico.IO_BANK0_BASE + pico.IO_BANK0_PROC1_INTF0_OFFSET, 4, 4),
    .proc1_ints = &mmio.Reg(u32).initMultiple(pico.IO_BANK0_BASE + pico.IO_BANK0_PROC1_INTS0_OFFSET, 4, 4),
    .dormant_wake_inte = &mmio.Reg(u32).initMultiple(pico.IO_BANK0_BASE + pico.IO_BANK0_DORMANT_WAKE_INTE0_OFFSET, 4, 4),
    .dormant_wake_intf = &mmio.Reg(u32).initMultiple(pico.IO_BANK0_BASE + pico.IO_BANK0_DORMANT_WAKE_INTF0_OFFSET, 4, 4),
    .dormant_wake_ints = &mmio.Reg(u32).initMultiple(pico.IO_BANK0_BASE + pico.IO_BANK0_DORMANT_WAKE_INTS0_OFFSET, 4, 4),

    .sio = .{
        .in = sio.Sio.gpio_in,
        .out = sio.Sio.gpio_out,
        .set = sio.Sio.gpio_out_set,
        .clr = sio.Sio.gpio_out_clr,
        .xor = sio.Sio.gpio_out_xor,
        .oe = sio.Sio.gpio_oe,
        .oe_set = sio.Sio.gpio_oe_set,
        .oe_clr = sio.Sio.gpio_oe_clr,
        .oe_xor = sio.Sio.gpio_oe_xor,
    },
};

const qspi = BankRegs {
    .status = &mmio.Reg(u32).initMultiple(pico.IO_QSPI_BASE, pico.NUM_QSPI_GPIOS, 8),
    .ctrl = &mmio.Reg(u32).initMultiple(pico.IO_QSPI_BASE + 4, pico.NUM_QSPI_GPIOS, 8),
    .pads = &mmio.Reg(PadReg).initMultiple(
        pico.PADS_QSPI_BASE + pico.PADS_QSPI_GPIO_QSPI_SCLK_OFFSET, pico.NUM_QSPI_GPIOS, 4),

    .intr = &mmio.Reg(u32).initMultiple(pico.IO_QSPI_BASE + pico.IO_QSPI_INTR_OFFSET, 1, 4),
    .proc0_inte = &mmio.Reg(u32).initMultiple(pico.IO_QSPI_BASE + pico.IO_QSPI_PROC0_INTE_OFFSET, 1, 4),
    .proc0_intf = &mmio.Reg(u32).initMultiple(pico.IO_QSPI_BASE + pico.IO_QSPI_PROC0_INTF_OFFSET, 1, 4),
    .proc0_ints = &mmio.Reg(u32).initMultiple(pico.IO_QSPI_BASE + pico.IO_QSPI_PROC0_INTS_OFFSET, 1, 4),
    .proc1_inte = &mmio.Reg(u32).initMultiple(pico.IO_QSPI_BASE + pico.IO_QSPI_PROC1_INTE_OFFSET, 1, 4),
    .proc1_intf = &mmio.Reg(u32).initMultiple(pico.IO_QSPI_BASE + pico.IO_QSPI_PROC1_INTF_OFFSET, 1, 4),
    .proc1_ints = &mmio.Reg(u32).initMultiple(pico.IO_QSPI_BASE + pico.IO_QSPI_PROC1_INTS_OFFSET, 1, 4),
    .dormant_wake_inte = &mmio.Reg(u32).initMultiple(pico.IO_QSPI_BASE + pico.IO_QSPI_DORMANT_WAKE_INTE_OFFSET, 1, 4),
    .dormant_wake_intf = &mmio.Reg(u32).initMultiple(pico.IO_QSPI_BASE + pico.IO_QSPI_DORMANT_WAKE_INTF_OFFSET, 1, 4),
    .dormant_wake_ints = &mmio.Reg(u32).initMultiple(pico.IO_QSPI_BASE + pico.IO_QSPI_DORMANT_WAKE_INTS_OFFSET, 1, 4),

    .sio = .{
        .in = sio.Sio.gpio_hi_in,
        .out = sio.Sio.gpio_hi_out,
        .set = sio.Sio.gpio_hi_out_set,
        .clr = sio.Sio.gpio_hi_out_clr,
        .xor = sio.Sio.gpio_hi_out_xor,
        .oe = sio.Sio.gpio_hi_oe,
        .oe_set = sio.Sio.gpio_hi_oe_set,
        .oe_clr = sio.Sio.gpio_hi_oe_clr,
        .oe_xor = sio.Sio.gpio_hi_oe_xor,
    },
};
