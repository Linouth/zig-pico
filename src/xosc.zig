const regs = @import("rp2040.zig").registers;

var initialized: bool = false;

pub fn init(comptime cycles_delay: usize) void {
    if (cycles_delay >= (1 << 13) * 256) {
        @compileError("XOSC: Max delay is 0x1fff00 cycles");
    }

    regs.XOSC.STARTUP.modify(.{
        .DELAY = cycles_delay / 256,
    });

    regs.XOSC.CTRL.modify(.{
        .ENABLE = 0xfab,
    });

    while (regs.XOSC.STATUS.read().STABLE != 1) {}
}

pub fn waitCycles(cycles: u8) void {
    regs.XOSC.COUNT.raw = cycles;
    while (regs.XOSC.COUNT.read() != 0) {}
}
