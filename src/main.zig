const gpio = @import("gpio.zig");
const pico = @import("pico.zig");
const timer = @import("timer.zig");
const nvic = @import("nvic.zig");
const resets = @import("resets.zig");

pub fn main() void {
    // Disable all interrupts
    nvic.reset();

    // Reset all peripherals, except for some critical blocks (e.g. XIP)
    resets.set(&resets.critical_blocks, .{.invert = true});
    resets.clear(&.{ .io_bank0, .pads_bank0, .timer }, .{.wait = true});

    var led = gpio.Gpio.init(25, .{});

    var alarm = timer.Alarm.init(0, alarmCb, &led) catch unreachable;
    alarm.arm(.{ .periodic = 1 * 1000 * 1000 });

    while (true) {
        //led.toggle();
        busySleep(100_000_00);
    }
}

fn alarmCb(context: ?*c_void) void {
    const led = @ptrCast(*gpio.Gpio, @alignCast(@alignOf(gpio.Gpio), context));
    led.toggle();
}

fn busySleep(comptime cycles: u32) void {
    var i: u32 = 0;
    while (i < (cycles)) : (i += 1) {
        asm volatile ("nop");
    }
}
