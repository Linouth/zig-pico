const gpio = @import("gpio.zig");
const pico = @import("pico.zig");
const timer = @import("timer.zig");

const resets: struct {
    ptr: *u32 = @intToPtr(*u32, pico.RESETS_BASE),

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
        all = 0xffffffff
    };

    fn config(self: Resets, peripherals: []const Peripherals) void {
        var out: u32 = 0;
        for (peripherals) |p| {
            out += @enumToInt(p);
        }
        self.ptr.* &= ~out;
    }

    fn set(self: Resets, peripheral: Peripherals) void {
        self.ptr.* |= @enumToInt(peripheral);
    }

    fn clear(self: Resets, peripheral: Peripherals) void {
        self.ptr.* &= ~@enumToInt(peripheral);
    }
} = .{};

pub fn main() void {
    // Enable IO_BANK0 and PADS_BANK0 peripherals
    //resets.config(&.{ .io_bank0, .pads_bank0, .timer });
    resets.config(&.{ .all });

    var led = gpio.Gpio.init(25, .{});

//    @breakpoint();

    const alarm = timer.Alarm.init(0, alarmCb, &led) catch unreachable;
    alarm.arm(.{ .periodic = 10000 });

    while (true) {
        timer.Alarm.irqHandler();
        //led.toggle();
        busySleep(100_000);
    }
}

fn alarmCb(context: ?*c_void) void {
    const led = @ptrCast(*gpio.Gpio, @alignCast(@alignOf(gpio.Gpio), context));
    led.toggle();
    //@breakpoint();
}

fn busySleep(comptime cycles: u32) void {
    var i: u32 = 0;
    while (i < (cycles)) : (i += 1) {
        asm volatile ("nop");
    }
}

