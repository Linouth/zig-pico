const std = @import("std");

const crt0 = @import("crt0.zig");

const chip = @import("rp2040.zig");
const regs = chip.registers;

pub const Irq = enum {
    timer_irq_0,
    timer_irq_1,
    timer_irq_2,
    timer_irq_3,
    pwm_irq_wrap,
    usbctrl_irq,
    xip_irq,
    pio0_irq_0,
    pio0_irq_1,
    pio1_irq_0,
    pio1_irq_1,
    dma_irq_0,
    dma_irq_1,
    io_irq_bank0,
    io_irq_qspi,
    sio_irq_proc0,
    sio_irq_proc1,
    clocks_irq,
    spi0_irq,
    spi1_irq,
    uart0_irq,
    uart1_irq,
    adc_irq_fifo,
    i2c0_irq,
    i2c1_irq,
    rtc_irq,

    irq26,
    irq27,
    irq28,
    irq29,
    irq30,
    irq31,

    pub fn enable(comptime self: Irq, comptime priority: u2, comptime vector: ?chip.InterruptVector) void {
        self.clear();

        // Set bit in the Interrupt Set Enable Register
        const irq_index = @enumToInt(self);
        regs.PPB.NVIC_ISER.raw = @as(u32, 1) << irq_index;

        self.setPriority(priority);

        if (vector) |vec| {
            // Convert vector table into an array of vectors for easy access
            var vectors = @ptrCast([*]chip.InterruptVector, &crt0.__vectors.TIMER_IRQ_0);
            vectors[irq_index] = vec;
        }

    }

    pub fn disable(self: Irq) void {
        regs.PPB.NVIC_ICER.raw = @as(u32, 1) << @enumToInt(self);
    }

    pub fn clear(self: Irq) void {
        regs.PPB.NVIC_ICPR.raw = @as(u32, 1) << @enumToInt(self);
    }

    pub fn setPriority(comptime self: Irq, comptime priority: u2) void {
        const index = @enumToInt(self);
        const ipr = regs.getNumberedField(regs.PPB, "NVIC_IPR{d}", index/4);
        const ip_name = comptime std.fmt.comptimePrint("IP_{d}", .{index});

        var tmp = ipr.read();
        @field(tmp, ip_name) = priority;
        ipr.write(tmp);
    }
};

pub fn getIPSR() Irq {
    const ipsr: u8 = asm volatile (
        "mrs r0, ipsr"
        : [ret] "={r0}" (-> u8)
    );

    return @intToEnum(Irq, @truncate(u5, ipsr-16));
}

/// Helper function that casts a 'c style context pointer' back into a Zig
/// type
pub inline fn castContext(comptime T: type, context: ?*anyopaque) *T {
    return @ptrCast(*T, @alignCast(@alignOf(T), context));
}

/// Disables all interrupts and clear pending. Usefull in the debugger
pub inline fn reset() void {
    regs.PPB.NVIC_ICER.raw = 0xffffffff;
    regs.PPB.NVIC_ICPR.raw = 0xffffffff;
}
