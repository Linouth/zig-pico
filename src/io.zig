const std = @import("std");

const nvic = @import("nvic.zig");
const chip = @import("rp2040.zig");
const regs = chip.registers;

const PIN_COUNT_BANK0 = 30;
const PIN_COUNT_QSPI = 5;

const Bank = enum {
    bank0,
    qspi
};

const PinBank0 = u5;

const PinQspi = enum {
    SCLK,
    SS,
    SD0,
    SD1,
    SD2,
    SD3,
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

var pins = [1]Pin{undefined} ** (PIN_COUNT_BANK0 + PIN_COUNT_QSPI);

/// This type controls the 'Pad' register for a specific pin. It can be passed
/// to other peripherals such as Gpio and Uart.
pub const Pin = struct {
    pin: u5,

    regs: *const RegSet,

    const Pull = enum(u2) {
        pull_up,
        pull_down,
        float,
    };

    const DriveStrength = enum(u2) {
        _2mA,
        _4mA,
        _8mA,
        _12mA,
    };

    const SlewRate = enum(u1) {
        slow,
        fast,
    };

    pub const PadConfig = struct {
        pull: Pull = .pull_down,
        drive_current: DriveStrength = ._4mA,
        slew_rate: SlewRate = .slow,
        schmitt_trigger: bool = true,
        input_enable: bool = true,
        output_disable: bool = false,
    };

    /// Create a new Pin instance for the specified pin. This does not do
    /// anything to the registers.
    pub fn init(comptime pin: anytype, comptime bank: Bank) Pin {
        const out = comptime .{
            .pin = pin,
            .regs = Regs.get(bank),
        };

        comptime pins[pin] = out;

        return out;
    }

    /// Configure a Pin. This sets the pad register with the provided
    /// configurations.
    pub fn configure(self: Pin, comptime config: PadConfig) Pin {
        const pad = self.regs.pad[self.pin];
        pad.modify(.{
            .SLEWFAST = @enumToInt(config.slew_rate),
            .SCHMITT = @boolToInt(config.schmitt_trigger),
            .PDE = switch (config.pull) {
                .pull_up, .float => 0,
                .pull_down => 1,
            },
            .PUE = switch (config.pull) {
                .pull_up => 1,
                .pull_down, .float => 0,
            },
            .DRIVE = @enumToInt(config.drive_current),
            .IE = @boolToInt(config.input_enable),
            .OD = @boolToInt(config.output_disable),
        });

        return self;
    }

    pub fn setFunction(self: Pin, func: Function) void {
        self.regs.ctrl[self.pin].raw = @enumToInt(func);
    }

    pub const Intr = struct {
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
            level_low: bool = false,
            level_high: bool = false,
            edge_low: bool = false,
            edge_high: bool = false,
        };
    };

    pub fn irqConfig(
        self: Pin,
        target: Intr.Target,
        triggers: Intr.TriggersBitfield
    ) void {
        nvic.Irq.clear(.io_irq_bank0);
        nvic.Irq.clear(.io_irq_qspi);
        self.irqAck();

        const inte = switch(target) {
            .proc0 => self.regs.proc0_inte,
            .proc1 => self.regs.proc1_inte,
            .dormant_wake => self.regs.dormant_wake_inte,
        };

        const mask = @as(u32, @bitCast(u4, triggers)) << (self.pin % 8) * 4;
        inte[self.pin/8].raw |= mask;
    }

    pub fn irqAck(self: Pin) void {
        {
            const intr = self.regs.intr[self.pin/8];
            intr.raw = @as(u32, 0xf) << 4 * (self.pin % 8);
        }

        // TODO: Check if these should be cleared, or if they are when pending
        // is cleared.
        //{
        //    const intf = self.regs.proc0_intf[self.pin/8];
        //    intr.raw = @as(u32, 0xf) << 4 * (self.pin % 8);
        //}
    }
};

pub const Gpio = struct {
    pin: Pin,

    regs: *const RegSet.Sio,

    /// Create a new Gpio instance using a specific Pin. This does not do
    /// anything to the registers.
    pub fn init(pin: Pin) Gpio {
        return .{
            .pin = pin,
            .regs = &pin.regs.sio,
        };
    }

    /// Configure the Gpio. This actually sets the function to 'SIO' (gpio) and
    /// clears previous states.
    pub fn configure(self: Gpio, output_enabled: bool) Gpio {
        self.pin.setFunction(.sio);

        self.clear();

        if (output_enabled) {
            self.regs.oe_set.raw = @as(u32, 1) << self.pin.pin;
        } else {
            self.regs.oe_clr.raw = @as(u32, 1) << self.pin.pin;
        }

        return self;
    }

    pub inline fn set(self: Gpio) void {
        self.regs.set.raw = @as(u32, 1) << self.pin.pin;
    }

    pub inline fn clear(self: Gpio) void {
        self.regs.clr.raw = @as(u32, 1) << self.pin.pin;
    }

    pub inline fn toggle(self: Gpio) void {
        self.regs.xor.raw = @as(u32, 1) << self.pin.pin;
    }
};

// Register stuff

// TODO: Find a better way to have a generic type for these registers. This
// should not be hard coded right here, but I could not thingof a better way.
// The 'rp2040.zig' regs file should have a generic type for any register that
// uses the same format.
const StatusType = *volatile StatusT;
const StatusT = chip.Mmio(32, packed struct {
    reserved0: u1,
    reserved1: u1,
    reserved2: u1,
    reserved3: u1,
    reserved4: u1,
    reserved5: u1,
    reserved6: u1,
    reserved7: u1,
    /// output signal from selected peripheral, before register override is applied
    OUTFROMPERI: u1,
    /// output signal to pad after register override is applied
    OUTTOPAD: u1,
    reserved8: u1,
    reserved9: u1,
    /// output enable from selected peripheral, before register override is applied
    OEFROMPERI: u1,
    /// output enable to pad after register override is applied
    OETOPAD: u1,
    reserved10: u1,
    reserved11: u1,
    reserved12: u1,
    /// input signal from pad, before override is applied
    INFROMPAD: u1,
    reserved13: u1,
    /// input signal to peripheral, after override is applied
    INTOPERI: u1,
    reserved14: u1,
    reserved15: u1,
    reserved16: u1,
    reserved17: u1,
    /// interrupt from pad before override is applied
    IRQFROMPAD: u1,
    reserved18: u1,
    /// interrupt to processors, after override is applied
    IRQTOPROC: u1,
    padding0: u1,
    padding1: u1,
    padding2: u1,
    padding3: u1,
    padding4: u1,
});
const CtrlType = *volatile CtrlT;
const CtrlT = chip.Mmio(32, packed struct {
    /// 0-31 -> selects pin function according to the gpio table\n
    /// 31 == NULL
    FUNCSEL: u5,
    reserved0: u1,
    reserved1: u1,
    reserved2: u1,
    OUTOVER: u2,
    reserved3: u1,
    reserved4: u1,
    OEOVER: u2,
    reserved5: u1,
    reserved6: u1,
    INOVER: u2,
    reserved7: u1,
    reserved8: u1,
    reserved9: u1,
    reserved10: u1,
    reserved11: u1,
    reserved12: u1,
    reserved13: u1,
    reserved14: u1,
    reserved15: u1,
    reserved16: u1,
    IRQOVER: u2,
    padding0: u1,
    padding1: u1,
});
const PadType = *volatile PadT;
const PadT = chip.Mmio(32, packed struct {
    /// Slew rate control. 1 = Fast, 0 = Slow
    SLEWFAST: u1,
    /// Enable schmitt trigger
    SCHMITT: u1,
    /// Pull down enable
    PDE: u1,
    /// Pull up enable
    PUE: u1,
    /// Drive strength.
    DRIVE: u2,
    /// Input enable
    IE: u1,
    /// Output disable. Has priority over output enable from peripherals
    OD: u1,
    padding0: u1,
    padding1: u1,
    padding2: u1,
    padding3: u1,
    padding4: u1,
    padding5: u1,
    padding6: u1,
    padding7: u1,
    padding8: u1,
    padding9: u1,
    padding10: u1,
    padding11: u1,
    padding12: u1,
    padding13: u1,
    padding14: u1,
    padding15: u1,
    padding16: u1,
    padding17: u1,
    padding18: u1,
    padding19: u1,
    padding20: u1,
    padding21: u1,
    padding22: u1,
    padding23: u1,
});
const SioType = *volatile chip.MmioInt(32, u30);
const IntrType = *volatile chip.MmioInt(32, u32);


fn genRegLut(
    comptime T: type,
    comptime count: comptime_int,
    comptime parent: anytype,
    comptime fmt: []const u8,
) [count]T {
    var out: [count]T = undefined;

    var i: comptime_int = 0;
    inline while (i < count) : (i += 1) {
        out[i] = @ptrCast(T, regs.getNumberedField(parent, fmt, i));
    }

    return out;
}

const RegSet = struct {
    status: []const StatusType,
    ctrl: []const CtrlType,
    pad: []const PadType,

    intr: []const IntrType,
    proc0_inte: []const IntrType,
    proc0_intf: []const IntrType,
    proc0_ints: []const IntrType,
    proc1_inte: []const IntrType,
    proc1_intf: []const IntrType,
    proc1_ints: []const IntrType,
    dormant_wake_inte: []const IntrType,
    dormant_wake_intf: []const IntrType,
    dormant_wake_ints: []const IntrType,

    sio: Sio,

    const Sio = struct {
        in: SioType,

        out: SioType,
        set: SioType,
        clr: SioType,
        xor: SioType,

        oe: SioType,
        oe_set: SioType,
        oe_clr: SioType,
        oe_xor: SioType,
    };
};

const Regs = struct {
    const bank0 = RegSet {
        .status = &genRegLut(StatusType, 30, regs.IO_BANK0, "GPIO{d}_STATUS"),
        .ctrl = &genRegLut(CtrlType, 30, regs.IO_BANK0, "GPIO{d}_CTRL"),
        .pad = &genRegLut(PadType, 30, regs.PADS_BANK0, "GPIO{d}"),

        .intr = &genRegLut(IntrType, 4, regs.IO_BANK0, "INTR{d}"),
        .proc0_inte = &genRegLut(IntrType, 4, regs.IO_BANK0, "PROC0_INTE{d}"),
        .proc0_intf = &genRegLut(IntrType, 4, regs.IO_BANK0, "PROC0_INTF{d}"),
        .proc0_ints = &genRegLut(IntrType, 4, regs.IO_BANK0, "PROC0_INTS{d}"),
        .proc1_inte = &genRegLut(IntrType, 4, regs.IO_BANK0, "PROC1_INTE{d}"),
        .proc1_intf = &genRegLut(IntrType, 4, regs.IO_BANK0, "PROC1_INTF{d}"),
        .proc1_ints = &genRegLut(IntrType, 4, regs.IO_BANK0, "PROC1_INTS{d}"),
        .dormant_wake_inte = &genRegLut(IntrType, 4, regs.IO_BANK0, "DORMANT_WAKE_INTE{d}"),
        .dormant_wake_intf = &genRegLut(IntrType, 4, regs.IO_BANK0, "DORMANT_WAKE_INTF{d}"),
        .dormant_wake_ints = &genRegLut(IntrType, 4, regs.IO_BANK0, "DORMANT_WAKE_INTS{d}"),

        .sio = .{
            .in = @ptrCast(SioType, regs.SIO.GPIO_IN),
            .out = @ptrCast(SioType, regs.SIO.GPIO_OUT),
            .set = @ptrCast(SioType, regs.SIO.GPIO_OUT_SET),
            .clr = @ptrCast(SioType, regs.SIO.GPIO_OUT_CLR),
            .xor = @ptrCast(SioType, regs.SIO.GPIO_OUT_XOR),
            .oe = @ptrCast(SioType, regs.SIO.GPIO_OE),
            .oe_set = @ptrCast(SioType, regs.SIO.GPIO_OE_SET),
            .oe_clr = @ptrCast(SioType, regs.SIO.GPIO_OE_CLR),
            .oe_xor = @ptrCast(SioType, regs.SIO.GPIO_OE_XOR),
        },
    };

    const qspi = RegSet {
        .status = &.{
            @ptrCast(StatusType, regs.IO_QSPI.GPIO_QSPI_SCLK_STATUS),
            @ptrCast(StatusType, regs.IO_QSPI.GPIO_QSPI_SS_STATUS),
            @ptrCast(StatusType, regs.IO_QSPI.GPIO_QSPI_SD0_STATUS),
            @ptrCast(StatusType, regs.IO_QSPI.GPIO_QSPI_SD1_STATUS),
            @ptrCast(StatusType, regs.IO_QSPI.GPIO_QSPI_SD2_STATUS),
            @ptrCast(StatusType, regs.IO_QSPI.GPIO_QSPI_SD3_STATUS),
        },
        .ctrl = &.{
            @ptrCast(CtrlType, regs.IO_QSPI.GPIO_QSPI_SCLK_CTRL),
            @ptrCast(CtrlType, regs.IO_QSPI.GPIO_QSPI_SS_CTRL),
            @ptrCast(CtrlType, regs.IO_QSPI.GPIO_QSPI_SD0_CTRL),
            @ptrCast(CtrlType, regs.IO_QSPI.GPIO_QSPI_SD1_CTRL),
            @ptrCast(CtrlType, regs.IO_QSPI.GPIO_QSPI_SD2_CTRL),
            @ptrCast(CtrlType, regs.IO_QSPI.GPIO_QSPI_SD3_CTRL),
        },
        .pad = &.{
            @ptrCast(PadType, regs.PADS_QSPI.GPIO_QSPI_SCLK),
            @ptrCast(PadType, regs.PADS_QSPI.GPIO_QSPI_SS),
            @ptrCast(PadType, regs.PADS_QSPI.GPIO_QSPI_SD0),
            @ptrCast(PadType, regs.PADS_QSPI.GPIO_QSPI_SD1),
            @ptrCast(PadType, regs.PADS_QSPI.GPIO_QSPI_SD2),
            @ptrCast(PadType, regs.PADS_QSPI.GPIO_QSPI_SD3),
        },

        .intr = &genRegLut(IntrType, 1, regs.IO_BANK0, "INTR{d}"),
        .proc0_inte = &genRegLut(IntrType, 1, regs.IO_BANK0, "PROC0_INTE{d}"),
        .proc0_intf = &genRegLut(IntrType, 1, regs.IO_BANK0, "PROC0_INTF{d}"),
        .proc0_ints = &genRegLut(IntrType, 1, regs.IO_BANK0, "PROC0_INTS{d}"),
        .proc1_inte = &genRegLut(IntrType, 1, regs.IO_BANK0, "PROC1_INTE{d}"),
        .proc1_intf = &genRegLut(IntrType, 1, regs.IO_BANK0, "PROC1_INTF{d}"),
        .proc1_ints = &genRegLut(IntrType, 1, regs.IO_BANK0, "PROC1_INTS{d}"),
        .dormant_wake_inte = &genRegLut(IntrType, 1, regs.IO_BANK0, "DORMANT_WAKE_INTE{d}"),
        .dormant_wake_intf = &genRegLut(IntrType, 1, regs.IO_BANK0, "DORMANT_WAKE_INTF{d}"),
        .dormant_wake_ints = &genRegLut(IntrType, 1, regs.IO_BANK0, "DORMANT_WAKE_INTS{d}"),

        .sio = .{
            .in = @ptrCast(SioType, regs.SIO.GPIO_HI_IN),
            .out = @ptrCast(SioType, regs.SIO.GPIO_HI_OUT),
            .set = @ptrCast(SioType, regs.SIO.GPIO_HI_OUT_SET),
            .clr = @ptrCast(SioType, regs.SIO.GPIO_HI_OUT_CLR),
            .xor = @ptrCast(SioType, regs.SIO.GPIO_HI_OUT_XOR),
            .oe = @ptrCast(SioType, regs.SIO.GPIO_HI_OE),
            .oe_set = @ptrCast(SioType, regs.SIO.GPIO_HI_OE_SET),
            .oe_clr = @ptrCast(SioType, regs.SIO.GPIO_HI_OE_CLR),
            .oe_xor = @ptrCast(SioType, regs.SIO.GPIO_HI_OE_XOR),
        },
    };

    fn get(bank: Bank) *const RegSet {
        return switch (bank) {
            .bank0 => &bank0,
            .qspi => &qspi,
        };
    }
};
