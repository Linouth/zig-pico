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

pub const Alarm = struct {
    const CallbackFn = fn(?*c_void) void;

    const AlarmError = error {
        AlreadyInUse,
    };

    var alarms: [4]?Alarm = .{null} ** 4;

    const Mode = union(enum) {
        unspecified,
        oneshot: u32,
        periodic: u32,
    };

    id: u2,
    callback: CallbackFn,
    context: ?*c_void,
    mode: Mode = .unspecified,

    pub fn init(id: u2, comptime callback: CallbackFn, context: ?*c_void) !*Alarm {
        if (alarms[id]) |_| {
            return error.AlreadyInUse;
        } else {
            alarms[id] = Alarm {
                .id = id,
                .callback = callback,
                .context = context,
            };
        }

        // TODO: Probably check if the irq bits are already set, and if they are
        // it is most likely that the other core is using the alarm (or a bug)
        // TODO: Add spinlock for when changing IRQ registers
        //
        // TODO: Configure IRQ

        return &alarms[id].?;
    }

    pub fn deinit(self: Alarm) void {
        alarms[self.id] = null;
        // TODO: Do deinit stuff (dearm, disable irq)
    }

    pub fn arm(self: *Alarm, mode: Mode) void {
        if (mode == .unspecified)
            return;
        self.mode = mode;

        const curr_time = getTimeLower();
        const next_time: u32 = switch (mode) {
            .unspecified => return,
            .oneshot, .periodic => |delta| curr_time +% delta,
        };

        // TODO: Arm alarm
    }

    pub fn stop(self: *Alarm) void {

    }

    pub fn irqHandler() void {
        // TODO: Get Alarm id
        const id = 0;

        if (alarms[id]) |alarm| {
            alarm.callback(alarm.context);

            // TODO: Check if periodic, and if it is, reset the alarm
            if (alarm.mode == .periodic) {

            }
        }
    }
};


/// Return the full current Timer counter
///
/// Returns the 64bit counter from the Timer peripheral
pub fn getTime() u64 {
    var hi = timer_hw.timerawh;

    return blk: {
        while (true) {
            const lo = timer_hw.timerawl;
            const hi_next = timer_hw.timerawh;
            if (hi_next == hi)
                break :blk (@as(u64, hi) << 32) | lo;
            hi = hi_next;
        }
    };
}

/// Faster way to return the current Timer counter.
///
/// NOTE: This function makes use of the latched registers in the Timer
/// peripheral. This means that it is unsafe to use this function if both cores
/// call it. Either use a lock, or use `getTime()` as this function prevents
/// this issue.
pub fn getTimeLatched() u64 {
    const lo = timer_hw.timelr;
    const hi = timer_hw.timehr;
    return (@as(u64, hi) << 32) | lo;
}

/// Get the current time in microseconds since peripheral reset.
///
/// Returns the lower word of the Timer counter.
pub fn getTimeLower() u32 {
    return timer_hw.timerawl;
}
