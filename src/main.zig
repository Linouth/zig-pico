const gpio = @import("gpio.zig");

const RESETS_BASE: u32 = 0x4000c000;

const resets: struct {
    ptr: *u32 = @intToPtr(*u32, 0x4000c000),

    const Resets = @This();

    const Peripherals = enum(u32) {
        adc = 1 << 0,
        busctrl = 1 << 1,
        dma = 1 << 2,
        i2c0 = 1 << 3,
        i2c1 = 1 << 4,
        io_bank0 = 1 << 5,
        io_qspi = 1 << 6,
        jtag = 1 << 7,
        pads_bank0 = 1 << 8,
        pads_qspi = 1 << 9,
        pio0 = 1 << 10,
        pio1 = 1 << 11,
        pll_sys = 1 << 12,
        pll_usb = 1 << 13,
        pwm = 1 << 14,
        rtc = 1 << 15,
        spi0 = 1 << 16,
        spi1 = 1 << 17,
        syscfg = 1 << 18,
        sysinfo = 1 << 19,
        tbman = 1 << 20,
        timer = 1 << 21,
        uart0 = 1 << 22,
        uart1 = 1 << 23,
        usbctrl = 1 << 24,
    };

    fn config(self: Resets, peripherals: []const Peripherals) void {
        var out: u32 = 0;
        for (peripherals) |p| {
            out += @enumToInt(p);
        }
        self.ptr.* = ~out;
    }

    fn set(self: Resets, peripheral: Peripheral) void {
        self.ptr.* |= @enumToInt(peripheral);
    }

    fn clear(self: Resets, peripheral: Peripheral) void {
        self.ptr.* &= ~@enumToInt(peripheral);
    }
} = .{};

pub fn main() void {
    // Enable IO_BANK0 and PADS_BANK0 peripherals
    resets.config(&.{ .io_bank0, .pads_bank0});

    const led = gpio.Gpio.init(25, .{});

    while (true) {
        led.toggle();
        busySleep(100_000);
    }
}

fn busySleep(comptime cycles: u32) void {
    const CYCLES = 133_000_000 / 1000;

    var i: u32 = 0;
    while (i < (cycles)) : (i += 1) {
        asm volatile ("nop");
    }
}

