const pico = @import("pico.zig");
const sio = @import("sio.zig").sio;

pub const Gpio = struct {
    pin: u5,
    mode: Mode,

    pad: *PadReg,
    bank: *GpioReg,

    sio: struct {
        in: *u32,

        out: *u32,
        set: *u32,
        clr: *u32,
        xor: *u32,

        oe: *u32,
        oe_set: *u32,
        oe_clr: *u32,
        oe_xor: *u32
    },


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

    pub fn init(comptime pin: u5, comptime config: GpioConfig) Gpio {
        switch (config.bank) {
            .bank0 => if (pin >= pico.NUM_BANK0_GPIOS)
                @compileError("There are only 30 GPIOs in BANK0."),
            .qspi => if (pin >= pico.NUM_QSPI_GPIOS)
                @compileError("There are only 5 GPIOs in the QSPI bank."),
        }

        const self = switch (config.bank) {
            .bank0 => Gpio {
                .pin = pin,
                .mode = config.mode,

                .pad = &pads_bank0[pin],
                .bank = &bank0[pin],
                .sio = .{
                    .in = &sio.gpio_in,

                    .out = &sio.gpio_out,
                    .set = &sio.gpio_out_set,
                    .clr = &sio.gpio_out_clr,
                    .xor = &sio.gpio_out_xor,

                    .oe = &sio.gpio_oe,
                    .oe_set = &sio.gpio_oe_set,
                    .oe_clr = &sio.gpio_oe_clr,
                    .oe_xor = &sio.gpio_oe_xor,
                },
            },

            .qspi => Gpio {
                .pin = pin,
                .mode = config.mode,

                .pad = &pads_qspi[pin],
                .bank = &qspi[pin],
                .sio = .{
                    .in = &sio.gpio_hi_in,

                    .out = &sio.gpio_hi_out,
                    .set = &sio.gpio_hi_out_set,
                    .clr = &sio.gpio_hi_out_clr,
                    .xor = &sio.gpio_hi_out_xor,

                    .oe = &sio.gpio_hi_oe,
                    .oe_set = &sio.gpio_hi_oe_set,
                    .oe_clr = &sio.gpio_hi_oe_clr,
                    .oe_xor = &sio.gpio_hi_oe_xor,
                },
            },
        };

        // Clear and configure output
        self.clear();

        self.setMode(config.mode);
        self.setPull(config.pull);
        self.setDriveCurrent(config.drive_current);
        self.enableSchmitt(config.schmitt_trigger);
        self.enableSlew(config.slew_fast);

        // Set gpio function
        self.bank.ctrl = @enumToInt(config.func);

        return self;
    }

    /// Configure internals for the specified mode (input, output, both)
    fn setMode(self: Gpio, mode: Mode) void {
        switch (mode) {
            .input => {
                self.pad.input_enable = 1;
                self.pad.output_disable = 1;
                self.sio.oe_clr.* = @as(u32, 1) << self.pin;
            },
            .output => {
                self.pad.input_enable = 0;
                self.pad.output_disable = 0;
                self.sio.oe_set.* = @as(u32, 1) << self.pin;
            },
            .input_output => {
                self.pad.input_enable = 1;
                self.pad.output_disable = 0;
                self.sio.oe_set.* = @as(u32, 1) << self.pin;
            },
            .none => {
                self.pad.input_enable = 0;
                self.pad.output_disable = 1;
                self.sio.oe_clr.* = @as(u32, 1) << self.pin;
            },
        }
    }

    /// Enable internal pull-up/-down resistors
    fn setPull(self: Gpio, pull: Pull) void {
        switch (pull) {
            .pull_up => {
                self.pad.pull_up = 1;
                self.pad.pull_down = 0;
            },
            .pull_down => {
                self.pad.pull_up = 0;
                self.pad.pull_down = 1;
            },
            .float => {
                self.pad.pull_up = 0;
                self.pad.pull_down = 0;
            },
        }
    }

    /// Set the maximum output drive current
    fn setDriveCurrent(self: Gpio, current: Current) void {
        self.pad.drive_current = current;
    }

    /// Enable/disable fast slewrate
    fn enableSlew(self: Gpio, slew: bool) void {
        self.pad.slew_fast = @boolToInt(slew);
    }

    /// Enable/disable schmitt trigger (input hysteresis)
    fn enableSchmitt(self: Gpio, schmitt: bool) void {
        self.pad.schmitt_trigger = @boolToInt(schmitt);
    }

    pub inline fn set(self: Gpio) void {
        self.sio.set.* = @as(u32, 1) << self.pin;
    }

    pub inline fn clear(self: Gpio) void {
        self.sio.clr.* = @as(u32, 1) << self.pin;
    }

    pub inline fn toggle(self: Gpio) void {
        self.sio.xor.* = @as(u32, 1) << self.pin;
    }
};

const GpioReg = packed struct {
    status: u32,
    ctrl: u32,
};
const bank0 = @intToPtr([*]GpioReg, pico.IO_BANK0_BASE)[0..pico.NUM_BANK0_GPIOS];
const qspi = @intToPtr([*]GpioReg, pico.IO_QSPI_BASE)[0..pico.NUM_QSPI_GPIOS];

const PadReg = packed struct {
    slew_fast: u1,
    schmitt_trigger: u1,
    pull_down: u1,
    pull_up: u1,
    drive_current: Gpio.Current,
    input_enable: u1,
    output_disable: u1,
};
const pads_bank0 = @intToPtr([*]PadReg,
    pico.PADS_BANK0_BASE+pico.PADS_BANK0_GPIO0_OFFSET)[0..pico.NUM_BANK0_GPIOS];
const pads_qspi = @intToPtr([*]PadReg,
    pico.PADS_QSPI_BASE+pico.PADS_BANK0_QSPI_OFFSET)[0..pico.NUM_QSPI_GPIOS];
