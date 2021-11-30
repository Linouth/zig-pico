const std = @import("std");
const builtin = std.builtin;

const main = @import("main.zig");
const systickHandler = @import("timer.zig").systickHandler;

const PPB_BASE: u32 = 0xe0000000;
const VTOR: u32 = 0xed08;

const SIO_BASE: u32 = 0xd0000000;

extern var __stack: usize;

export fn _entry() linksection(".reset.entry") callconv(.Naked) noreturn {
    const vtor = @intToPtr(*usize, PPB_BASE + VTOR);
    vtor.* = @ptrToInt(&__vectors);

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

extern var __bss_start: usize;
extern const __bss_end: usize;

const _wait_for_vector = @intToPtr(fn() noreturn, 0x0137);

fn _reset() linksection(".reset") callconv(.Naked) noreturn {
    const cpuid = @intToPtr(*u32, SIO_BASE);
    if (cpuid.* != 0) _wait_for_vector();

    // TODO: Missing data section copy, but not yet needed.

    // Clear bss
    const bss_size = @ptrToInt(&__bss_end) - @ptrToInt(&__bss_start);
    @memset(@ptrCast([*]u8, &__bss_start), 0, bss_size);

    //main.main();
    @call(.{ .modifier = .never_inline }, main.main, .{});

    while (true) {
        @breakpoint();
    }
}

pub fn panic(msg: []const u8, trace: ?*builtin.StackTrace) noreturn {
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

const VectorTable = packed struct {
    const VectorNoReturn = fn() callconv(.Naked) noreturn;
    const Vector = fn() void;

    stack: usize,

    reset: VectorNoReturn,
    nmi: Vector = unhandledHandler,
    hardfault: Vector = unhandledHandler,
    invalid0: Vector = @intToPtr(Vector, 0xfffffffa),
    invalid1: Vector = @intToPtr(Vector, 0xfffffffa),
    invalid2: Vector = @intToPtr(Vector, 0xfffffffa),
    invalid3: Vector = @intToPtr(Vector, 0xfffffffa),
    invalid4: Vector = @intToPtr(Vector, 0xfffffffa),
    invalid5: Vector = @intToPtr(Vector, 0xfffffffa),
    invalid6: Vector = @intToPtr(Vector, 0xfffffffa),
    svcall: Vector = unhandledHandler,
    invalid7: Vector = @intToPtr(Vector, 0xfffffffa),
    invalid8: Vector = @intToPtr(Vector, 0xfffffffa),
    pendsv: Vector = unhandledHandler,
    systick: Vector = unhandledHandler,

    timer_irq_0: Vector = dummyHandler,
    timer_irq_1: Vector = dummyHandler,
    timer_irq_2: Vector = dummyHandler,
    timer_irq_3: Vector = dummyHandler,
    pwm_irq_wrap: Vector = dummyHandler,
    usbctrl_irq: Vector = dummyHandler,
    xip_irq: Vector = dummyHandler,
    pio0_irq_0: Vector = dummyHandler,
    pio0_irq_1: Vector = dummyHandler,
    pio1_irq_0: Vector = dummyHandler,
    pio1_irq_1: Vector = dummyHandler,
    dma_irq_0: Vector = dummyHandler,
    dma_irq_1: Vector = dummyHandler,
    io_irq_bank0: Vector = dummyHandler,
    io_irq_qspi: Vector = dummyHandler,
    sio_irq_proc0: Vector = dummyHandler,
    sio_irq_proc1: Vector = dummyHandler,
    clocks_irq: Vector = dummyHandler,
    spi0_irq: Vector = dummyHandler,
    spi1_irq: Vector = dummyHandler,
    uart0_irq: Vector = dummyHandler,
    uart1_irq: Vector = dummyHandler,
    adc_irq_fifo: Vector = dummyHandler,
    i2c0_irq: Vector = dummyHandler,
    i2c1_irq: Vector = dummyHandler,
    rtc_irq: Vector = dummyHandler,

    irq26: Vector = @intToPtr(Vector, 0xfffffffa),
    irq27: Vector = @intToPtr(Vector, 0xfffffffa),
    irq28: Vector = @intToPtr(Vector, 0xfffffffa),
    irq29: Vector = @intToPtr(Vector, 0xfffffffa),
    irq30: Vector = @intToPtr(Vector, 0xfffffffa),
    irq31: Vector = @intToPtr(Vector, 0xfffffffa),
};

const __vectors linksection(".vector_table") = VectorTable {
    .stack = 0x20040000,
    //.stack = @ptrToInt(&__stack), // Compiler bug? :C
    .reset = _reset,
    //.nmi = dummyHandler,
    //.hardfault = dummyHandler,
    //.svcall = dummyHandler,
    //.pendsv = dummyHandler,
    .systick = systickHandler,
};
