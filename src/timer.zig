const std = @import("std");
const pico = @import("pico.zig");

const TimerRegs = packed struct {
    timehw: u32,
    timelw: u32,
    timehr: u32,
    timelr: u32,
    alarm0: u32,
    alarm1: u32,
    alarm2: u32,
    alarm3: u32,
    armed: u32,
    timerawh: u32,
    timerawl: u32,
    dbgpause: u32,
    pause: u32,
    intr: u32,
    inte: u32,
    intf: u32,
    ints: u32,
};
const timer_hw = @intToPtr(*TimerRegs, pico.TIMER_BASE);

// TODO: Use Timer peripheral instead of ARM systick.

/// A timer based on ALARM4 from the Timer peripheral
/// Can only be used if there are less than 4 Alarms configured
///
/// Should only be used if you need more timers than the 4 alarms
const SoftTimer = struct {};

/// Alarm from the Timer peripheral
const Alarm = struct {};

/// Return the full current Timer counter
fn getTime() u64;

/// Return the lower word of the current Timer counter
fn getTimeLower() u32;

pub fn systickHandler() void {
    @breakpoint();

    var i: u8 = 0;
    while (i < timer_count) : (i += 1) {
        const timer = &timers[i];
        if (timer.status == .running) {
            timer.value -= 1;

            if (timer.value == 0) {
                switch (timer.mode) {
                    .oneshot => timer.status = .stopped,
                    .periodic => timer.value = timer.period,
                }

                timer.callback();
            }
        }
    }
}
