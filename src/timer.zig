const std = @import("std");
const nvic = @import("nvic.zig");

const regs = @import("rp2040.zig").registers;

pub const Alarm = struct {
    const CallbackFn = fn(?*anyopaque) void;

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
    context: ?*anyopaque,
    mode: Mode = .unspecified,

    pub fn init(comptime id: u2, comptime callback: CallbackFn, context: ?*anyopaque) !*Alarm {
        if (alarms[id]) |_| {
            return error.AlreadyInUse;
        } else {
            alarms[id] = Alarm {
                .id = id,
                .callback = callback,
                .context = context,
            };
        }

        const irq = @intToEnum(nvic.Irq, @enumToInt(nvic.Irq.timer_irq_0) + id);

        // Clear pending interrupt
        irq.clear();
        regs.TIMER.INTR.raw = @as(u4, 1) << @truncate(u2, id);

        // Enable interrupt
        irq.enable(0, .{ .C = irqHandler });
        regs.TIMER.INTE.raw |= @as(u4, 1) << id;

        return &alarms[id].?;
    }

    pub fn get(id: u2) ?*Alarm {
        if (alarms[id]) |*alarm| {
            return alarm;
        }
        return null;
    }

    pub fn deinit(self: Alarm) void {
        // Disarm alarm
        self.stop();

        // Disable interrupt generation and reception
        regs.TIMER.INTE.raw &= ~(@as(u4, 1) << self.id);
        @intToEnum(nvic.Irq, @enumToInt(nvic.Irq.timer_irq_0) + self.id).disable();

        alarms[self.id] = null;
    }

    // TODO: Check if we were quick enough with setting the alarm
    pub fn arm(self: *Alarm, mode: Mode) void {
        if (mode == .unspecified)
            return;

        self.mode = mode;
        self.setAlarmAndArm();
    }

    pub fn stop(self: Alarm) void {
        regs.TIMER.ARMED.raw = @as(u4, 1) << self.id;
    }

    pub fn force(self: Alarm) void {
        regs.TIMER.INTF.raw |= @as(u4, 1) << self.id;
    }

    fn setAlarmAndArm(self: Alarm) void {
        const curr_time = getTimeLower();
        const next_time: u32 = switch (self.mode) {
            .unspecified => return,
            .oneshot, .periodic => |delta| curr_time +% delta,
        };

        const alarm_reg = switch (self.id) {
            0 => regs.TIMER.ALARM0,
            1 => regs.TIMER.ALARM1,
            2 => regs.TIMER.ALARM2,
            3 => regs.TIMER.ALARM3,
        };
        alarm_reg.* = next_time;
    }

    pub fn irqHandler() callconv(.C) void {
        const id = @enumToInt(nvic.getIPSR());

        // Clear interrupt and force flag
        const bit = @as(u4, 1) << @truncate(u2, id);
        regs.TIMER.INTR.raw = bit;
        //regs.TIMER.INTF.raw &= ~bit;

        if (alarms[id]) |alarm| {
            alarm.callback(alarm.context);

            if (alarm.mode == .periodic) {
                alarm.setAlarmAndArm();
            }
        }
    }
};


/// Return the full current Timer counter
///
/// Returns the 64bit counter from the Timer peripheral
pub fn getTime() u64 {
    var hi = regs.TIMER.TIMERAWH.*;

    return blk: {
        while (true) {
            const lo = regs.TIMER.TIMERAWL.*;
            const hi_next = regs.TIMER.TIMERAWH.*;
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
/// call it. Either use a lock, or use `getTime()` as that function prevents
/// this issue.
pub fn getTimeLatched() u64 {
    const lo = regs.TIMER.TIMELR.*;
    const hi = regs.TIMER.TIMEHR.*;
    return (@as(u64, hi) << 32) | lo;
}

/// Get the current time in microseconds since peripheral reset.
///
/// Returns the lower word of the Timer counter.
pub fn getTimeLower() u32 {
    return regs.TIMER.TIMERAWL.*;
}
