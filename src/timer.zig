const std = @import("std");
const pico = @import("pico.zig");
const nvic = @import("nvic.zig");
const mmio = @import("mmio.zig");

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

    pub fn init(comptime id: u2, comptime callback: CallbackFn, context: ?*c_void) !*Alarm {
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
        nvic.clearIrq(irq);
        Regs.intr.write(@as(u4, 1) << @truncate(u2, id));

        // Enable interrupt
        nvic.enableIrq(irq, 0, irqHandler);
        Regs.inte.set(@as(u4, 1) << id);

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
        Regs.inte.clear(@as(u4, 1) << self.id);
        nvic.disableIrq(
            @intToEnum(nvic.Irq, @enumToInt(nvic.Irq.timer_irq_0) + self.id));

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
        Regs.armed.write(@as(u4, 1) << self.id);
    }

    pub fn force(self: Alarm) void {
        Regs.intf.set(@as(u4, 1) << self.id);
    }

    fn setAlarmAndArm(self: Alarm) void {
        const curr_time = getTimeLower();
        const next_time: u32 = switch (self.mode) {
            .unspecified => return,
            .oneshot, .periodic => |delta| curr_time +% delta,
        };

        const alarm_reg = switch (self.id) {
            0 => Regs.alarm0,
            1 => Regs.alarm1,
            2 => Regs.alarm2,
            3 => Regs.alarm3,
        };
        alarm_reg.write(next_time);
    }

    pub fn irqHandler() void {
        const id = @enumToInt(nvic.getIPSR());

        // Clear interrupt and force flag
        const bit = @as(u4, 1) << @truncate(u2, id);
        Regs.intr.write(bit);
        Regs.intf.clear(bit);

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
    var hi = Regs.timerawh.read();

    return blk: {
        while (true) {
            const lo = Regs.timerawl.read();
            const hi_next = Regs.timerawh.read();
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
    const lo = Regs.timelr.read();
    const hi = Regs.timehr.read();
    return (@as(u64, hi) << 32) | lo;
}

/// Get the current time in microseconds since peripheral reset.
///
/// Returns the lower word of the Timer counter.
pub fn getTimeLower() u32 {
    return Regs.timerawl.read();
}


//
// Registers
//

// Should be lowercase, since it is not a type; However I would like to have a
// struct with declared variables, but that cannot be done programmatically
// yet in zig (#6709).
const Regs: mmio.RegisterList(pico.TIMER_BASE, &.{
    .{ .name = "timehw", .type = u32 },
    .{ .name = "timelw", .type = u32 },
    .{ .name = "timehr", .type = u32 },
    .{ .name = "timelr", .type = u32 },
    .{ .name = "alarm0", .type = u32 },
    .{ .name = "alarm1", .type = u32 },
    .{ .name = "alarm2", .type = u32 },
    .{ .name = "alarm3", .type = u32 },
    .{ .name = "armed", .type = u32 },
    .{ .name = "timerawh", .type = u32 },
    .{ .name = "timerawl", .type = u32 },
    .{ .name = "dbgpause", .type = u32 },
    .{ .name = "pause", .type = u32 },
    .{ .name = "intr", .type = u32 },
    .{ .name = "inte", .type = u32 },
    .{ .name = "intf", .type = u32 },
    .{ .name = "ints", .type = u32 },
}) = .{};
