const std = @import("std");
const chip = @import("rp2040.zig");
const regs = chip.registers;

const builtin = std.builtin;

const nvic = @import("nvic.zig");
const resets = @import("resets.zig");
const clocks = @import("clocks.zig");

const app = @import("app");

extern var __stack: anyopaque;

pub var __vectors linksection(".vector_table") = chip.VectorTable{
    .initial_stack_pointer = 0x20040000,
    //.initial_stack_pointer = @ptrToInt(_stack),
    .Reset = .{ .Naked = _reset },
};

export fn _entry() linksection(".reset.entry") callconv(.Naked) noreturn {
    regs.PPB.VTOR.raw = @ptrToInt(&__vectors);

    asm volatile (
        // load SP and _reset into r1 and r2
        \\ldm r0!, {r1, r2}
        // Configure SP
        \\msr msp, r1
        // Jump to _reset
        \\bx r2
        :: [__vectors] "{r0}" (&__vectors),
    );
    unreachable;
}

extern var __bss_start: anyopaque;
extern var __bss_end: anyopaque;

fn _reset() linksection(".reset") callconv(.Naked) noreturn {
    if (regs.SIO.CPUID.* != 0) unreachable;

    // TODO: Missing data section copy, but not yet needed.

    // Clear bss
    const bss_start = @ptrCast([*]u8, &__bss_start);
    const bss_end = @ptrCast([*]u8, &__bss_end);
    const bss_size = @ptrToInt(bss_end) - @ptrToInt(bss_start);
    std.mem.set(u8, bss_start[0..bss_size], 0);

    // Disable all interrupts
    nvic.reset();

    // Reset all peripherals, except for some critical blocks (e.g. XIP)
    resets.set(&resets.critical_blocks, .{.invert_input = true});

    // Initialize clocks
    clocks.init(12);

    //main.main();
    @call(.{ .modifier = .never_inline }, app.main, .{});

    while (true) {
        @breakpoint();
    }
}

pub fn panic(msg: []const u8, trace: ?*builtin.StackTrace) noreturn {
    _ = msg;
    _ = trace;

    while (true) {
        @breakpoint();
    }
}

fn dummyHandler() void { }

fn bkptHandler() void {
    @breakpoint();
}

// In .reset section so that it can still reach __vectors
fn unhandledHandler() linksection(".reset") void {
    var isr: u8 = asm volatile (
        "mrs r0, ipsr"
        : [ret] "={r0}" (-> u8)
    );
    isr >>= 4;

    @breakpoint();

    asm volatile (
        \\ldr r1, =__vectors
        \\ldr r0, [r0, #4]
        \\bx r0
    );
}

//pub const VectorTable = packed struct {
//    pub const VectorNoReturn = fn() callconv(.Naked) noreturn;
//    pub const Vector = fn() void;
//
//    stack: usize,
//
//    reset: VectorNoReturn,
//    nmi: Vector = unhandledHandler,
//    hardfault: Vector = unhandledHandler,
//    invalid0: Vector = @intToPtr(Vector, 0xfffffffa),
//    invalid1: Vector = @intToPtr(Vector, 0xfffffffa),
//    invalid2: Vector = @intToPtr(Vector, 0xfffffffa),
//    invalid3: Vector = @intToPtr(Vector, 0xfffffffa),
//    invalid4: Vector = @intToPtr(Vector, 0xfffffffa),
//    invalid5: Vector = @intToPtr(Vector, 0xfffffffa),
//    invalid6: Vector = @intToPtr(Vector, 0xfffffffa),
//    svcall: Vector = unhandledHandler,
//    invalid7: Vector = @intToPtr(Vector, 0xfffffffa),
//    invalid8: Vector = @intToPtr(Vector, 0xfffffffa),
//    pendsv: Vector = unhandledHandler,
//    systick: Vector = unhandledHandler,
//
//    timer_irq_0: Vector = dummyHandler,
//    timer_irq_1: Vector = dummyHandler,
//    timer_irq_2: Vector = dummyHandler,
//    timer_irq_3: Vector = dummyHandler,
//    pwm_irq_wrap: Vector = dummyHandler,
//    usbctrl_irq: Vector = dummyHandler,
//    xip_irq: Vector = dummyHandler,
//    pio0_irq_0: Vector = dummyHandler,
//    pio0_irq_1: Vector = dummyHandler,
//    pio1_irq_0: Vector = dummyHandler,
//    pio1_irq_1: Vector = dummyHandler,
//    dma_irq_0: Vector = dummyHandler,
//    dma_irq_1: Vector = dummyHandler,
//    io_irq_bank0: Vector = dummyHandler,
//    io_irq_qspi: Vector = dummyHandler,
//    sio_irq_proc0: Vector = dummyHandler,
//    sio_irq_proc1: Vector = dummyHandler,
//    clocks_irq: Vector = dummyHandler,
//    spi0_irq: Vector = dummyHandler,
//    spi1_irq: Vector = dummyHandler,
//    uart0_irq: Vector = dummyHandler,
//    uart1_irq: Vector = dummyHandler,
//    adc_irq_fifo: Vector = dummyHandler,
//    i2c0_irq: Vector = dummyHandler,
//    i2c1_irq: Vector = dummyHandler,
//    rtc_irq: Vector = dummyHandler,
//
//    irq26: Vector = @intToPtr(Vector, 0xfffffffa),
//    irq27: Vector = @intToPtr(Vector, 0xfffffffa),
//    irq28: Vector = @intToPtr(Vector, 0xfffffffa),
//    irq29: Vector = @intToPtr(Vector, 0xfffffffa),
//    irq30: Vector = @intToPtr(Vector, 0xfffffffa),
//    irq31: Vector = @intToPtr(Vector, 0xfffffffa),
//};
//
//pub var __vectors linksection(".vector_table") = VectorTable {
//    .stack = 0x20040000,
//    //.stack = @ptrToInt(&__stack), // Compiler bug? :C
//    .reset = _reset,
//    //.nmi = dummyHandler,
//    //.hardfault = dummyHandler,
//    //.svcall = dummyHandler,
//    //.pendsv = dummyHandler,
//    //.systick = systickHandler,
//};
