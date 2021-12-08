const gpio = @import("gpio.zig");
const pico = @import("pico.zig");
const timer = @import("timer.zig");
const nvic = @import("nvic.zig");
const resets = @import("resets.zig");
const mmio = @import("mmio.zig");

var led: gpio.Gpio = undefined;

pub fn main() void {
    // Disable all interrupts
    nvic.reset();

    // Reset all peripherals, except for some critical blocks (e.g. XIP)
    resets.set(&resets.critical_blocks, .{.invert_input = true});
    resets.clear(&.{ .io_bank0, .pads_bank0, .timer }, .{.wait_till_finished = true});

    gpio.setHandler(gpioCb);

    led = gpio.Gpio.init(25, .{});

    var gp0 = gpio.Gpio.init(0, .{});
    gp0.irqEnable(.proc0, .edge_high);

    var alarm = timer.Alarm.init(0, alarmCb, &led) catch unreachable;
    alarm.arm(.{ .periodic = 1 * 1000 * 1000 });

    while (true) {
        //led.toggle();
        busySleep(100_000);
    }
}

fn alarmCb(context: ?*c_void) void {
    const l = nvic.castContext(gpio.Gpio, context);
    l.toggle();
}

fn gpioCb(pin: gpio.Gpio, triggers: gpio.Intr.TriggersBitfield) void {
    led.toggle();
}

fn busySleep(comptime cycles: u32) void {
    var i: u32 = 0;
    while (i < (cycles)) : (i += 1) {
        asm volatile ("nop");
    }
}
