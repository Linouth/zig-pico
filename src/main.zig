const std = @import("std");

//const gpio = @import("gpio.zig");
const timer = @import("timer.zig");
const nvic = @import("nvic.zig");
const resets = @import("resets.zig");
//const clocks = @import("clocks.zig");

const io = @import("io.zig");

const chip = @import("rp2040.zig");
const regs = chip.registers;

var led: io.Gpio = undefined;

pub fn main() void {
    resets.clear(&.{ .io_bank0, .pads_bank0, .timer }, .{.wait_till_finished = true});

    nvic.Irq.enable(.io_irq_bank0, 0, .{ .C = gpioIrqHandler });

    var gp7_pin = io.Pin.init(7, .bank0).configure(.{});
    gp7_pin.irqConfig(.proc0, .{ .edge_high = true });

    var alarm = timer.Alarm.init(0, alarmCb, &led) catch unreachable;
    alarm.arm(.{ .periodic = 1 * 1000 * 1000 });

    const led_pin = io.Pin.init(16, .bank0).configure(.{});
    led = io.Gpio.init(led_pin).configure(true);

    while (true) {
        //regs.SIO.GPIO_OUT_XOR.raw = @as(u32, 1) << 16;
        //led.toggle();
        busySleep(100_000_00);
    }
}

fn alarmCb(context: ?*anyopaque) void {
    //const l = nvic.castContext(gpio.Gpio, context);
    //l.toggle();
    _ = context;
    led.toggle();
}
//
//fn gpioCb(pin: gpio.Gpio, triggers: gpio.Intr.TriggersBitfield) void {
//    _ = pin;
//    _ = triggers;
//
//    led.toggle();
//}

fn gpioIrqHandler() callconv(.C) void {
    @breakpoint();
    var gp7_pin = io.Pin.init(7, .bank0);
    gp7_pin.irqAck();
}

fn busySleep(comptime cycles: u32) void {
    var i: u32 = 0;
    while (i < (cycles)) : (i += 1) {
        asm volatile ("nop");
    }
}
