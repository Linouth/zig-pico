const pico = @import("pico.zig");
const crt0 = @import("crt0.zig");
const mmio = @import("mmio.zig");

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
};

pub fn enableIrq(comptime irq: Irq, comptime priority: u2, comptime vector: ?crt0.VectorTable.Vector) void {
    const irq_ind = @enumToInt(irq);
    clearIrq(irq);

    NvicRegs.iser.write(@as(u32, 1) << irq_ind);

    setPriority(irq, priority);

    // TODO: Add spinlock for changing vector table
    if (vector) |vec| {
        var vectors = @ptrCast([*]crt0.VectorTable.Vector, &crt0.__vectors.timer_irq_0);
        vectors[irq_ind] = vec;
    }
}

pub fn disableIrq(irq: Irq) void {
    NvicRegs.icer.write(@as(u32, 1) << @enumToInt(irq));
}

pub fn clearIrq(irq: Irq) void {
    NvicRegs.icpr.write(@as(u32, 1) << @enumToInt(irq));
}

pub fn setPriority(comptime irq: Irq, comptime priority: u2) void {
    const ind = @enumToInt(irq);

    var ipr = NvicRegs.ipr[ind/4].read();
    ipr[ind%4] = priority;
    NvicRegs.ipr[ind/4].write(ipr);
}

pub fn getIPSR() Irq {
    const ipsr: u8 = asm volatile (
        "mrs r0, ipsr"
        : [ret] "={r0}" (-> u8)
    );

    return @intToEnum(Irq, @truncate(u5, ipsr-16));
}

/// Helper function that casts a 'c style context pointer' back into a Zig
/// type
pub inline fn castContext(comptime T: type, context: ?*c_void) *T {
    return @ptrCast(*T, @alignCast(@alignOf(T), context));
}

/// Disables all interrupts and clear pending. Usefull in the debugger
pub inline fn reset() void {
    NvicRegs.icer.write(0xffffffff);
    NvicRegs.icpr.write(0xffffffff);
}

//
// Registers
//
const NvicRegs = struct {
    const iser = mmio.Reg32.init(pico.PPB_BASE + pico.M0PLUS_NVIC_ISER_OFFSET);
    const icer = mmio.Reg32.init(pico.PPB_BASE + pico.M0PLUS_NVIC_ICER_OFFSET);
    const ispr = mmio.Reg32.init(pico.PPB_BASE + pico.M0PLUS_NVIC_ISPR_OFFSET);
    const icpr = mmio.Reg32.init(pico.PPB_BASE + pico.M0PLUS_NVIC_ICPR_OFFSET);

    const ipr = mmio.Reg([4]u8).initMultiple(pico.PPB_BASE + pico.M0PLUS_NVIC_IPR0_OFFSET, 8);
};
