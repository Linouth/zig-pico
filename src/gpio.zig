

const IO_BANK0_BASE: u32 = 0x40014000;
const BANK0_COUNT = 30;

const IO_QSPI_BASE: u32 = 0x40018000;
const QSPI_COUNT = 6;

const PADS_BANK0_BASE: u32 = 0x4001c000;
const GP25_PAD: u32 = 0x68;

const PADS_QSPI_BASE: u32 = 0x40020000;
const PADS_CTRL_OFFSET: u32 = 4;

const SIO_BASE: u32 = 0xd0000000;

const Sio = extern struct {
    cpuid: u32,
    gpio_in: u32,
    gpio_hi_in: u32,
    _pad: u32,
    gpio_out: u32,
    gpio_out_set: u32,
    gpio_out_clr: u32,
    gpio_out_xor: u32,
    gpio_oe: u32,
    gpio_oe_set: u32,
    gpio_oe_clr: u32,
    gpio_oe_xor: u32,
};
const sio = @intToPtr(*Sio, SIO_BASE);

const GpioReg = packed struct {
    status: u32,
    ctrl: u32,
};
const bank0 = @intToPtr([*]GpioReg, IO_BANK0_BASE)[0..BANK0_COUNT];
const qspi = @intToPtr([*]GpioReg, IO_QSPI_BASE)[0..QSPI_COUNT];

const PadReg = packed struct {
    slew_fast: u1,
    schmitt_trigger: u1,
    pull_down: u1,
    pull_up: u1,
    drive_current: enum(u2) {
        current_2mA,
        current_4mA,
        current_8mA,
        current_12mA,
    },
    input_enable: u1,
    output_disable: u1,
};
const pads_bank0 = @intToPtr([*]PadReg, PADS_BANK0_BASE+PADS_CTRL_OFFSET)[0..BANK0_COUNT];
const pads_qspi = @intToPtr([*]PadReg, PADS_QSPI_BASE+PADS_CTRL_OFFSET)[0..QSPI_COUNT];

pub const Gpio = struct {
    pin: comptime u5,
    mode: comptime GpioMode,

    pad: comptime *PadReg,
    bank: comptime *GpioReg,

    const GpioConfig = struct {
        bank: GpioBank = .bank0,
        func: GpioFunction = .sio,
        mode: GpioMode = .input_output,
        pull: GpioPull = .pull_down,
    };

    const GpioBank = enum(u1) {
        bank0,
        qspi,
    };

    const GpioFunction = enum(u5) {
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

    const GpioMode = enum {
        input,
        output,
        input_output,
        none,
    };

    const GpioPull = enum {
        pull_up,
        pull_down,
        float,
    };

    const GpioPad = packed struct {
        slew_fast: u1 = 0,
        schmitt_trigger: u1 = 1,
        pull_down: u1 = 1,
        pull_up: u1 = 0,
        drive_current: enum(u2) {
            current_2mA,
            current_4mA,
            current_8mA,
            current_12mA,
        } = .current_4mA,
        input_enable: u1 = 1,
        output_disable: u1 = 0,
    };

    pub fn init(comptime pin: u5, comptime config: GpioConfig) Gpio {
        switch (config.bank) {
            .bank0 => if (pin >= BANK0_COUNT)
                @compileError("There are only 30 GPIOs in BANK0."),
            .qspi => if (pin >= QSPI_COUNT)
                @compileError("There are only 5 GPIOs in the QSPI bank."),
        }

        const self = Gpio{
            .pin = pin,
            .mode = config.mode,

            .pad = switch (config.bank) {
                .bank0 => &pads_bank0[pin],
                .qspi => &pads_qspi[pin],
            },
            .bank = switch (config.bank) {
                .bank0 => &bank0[pin],
                .qspi => &qspi[pin],
            },
        };

        // Clear and configure output
        self.clear();

        self.setMode(config.mode);
        self.setPull(config.pull);
        // TODO: Add configs for drive current, schmitt trigger and slewrate.

        // Set gpio function
        self.bank.ctrl = @enumToInt(config.func);

        return self;
    }

    inline fn setMode(self: Gpio, mode: GpioMode) void {
        switch (mode) {
            .input => {
                self.pad.input_enable = 1;
                self.pad.output_disable = 1;
                sio.gpio_oe_clr = @as(u32, 1) << self.pin;
            },
            .output => {
                self.pad.input_enable = 0;
                self.pad.output_disable = 0;
                sio.gpio_oe_set = @as(u32, 1) << self.pin;
            },
            .input_output => {
                self.pad.input_enable = 1;
                self.pad.output_disable = 0;
                sio.gpio_oe_set = @as(u32, 1) << self.pin;
            },
            .none => {
                self.pad.input_enable = 0;
                self.pad.output_disable = 1;
                sio.gpio_oe_clr = @as(u32, 1) << self.pin;
            },
        }
    }

    inline fn setPull(self: Gpio, pull: GpioPull) void {
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

    pub inline fn set(self: Gpio) void {
        sio.gpio_out_set = @as(u32, 1) << self.pin;
    }

    pub inline fn clear(self: Gpio) void {
        sio.gpio_out_clr = @as(u32, 1) << self.pin;
    }

    pub inline fn toggle(self: Gpio) void {
        sio.gpio_out_xor = @as(u32, 1) << self.pin;
    }
};
