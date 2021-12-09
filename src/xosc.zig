const pico = @import("pico.zig");
const mmio = @import("mmio.zig");

var initialized: bool = false;

pub fn init(comptime cycles_delay: usize) void {
    if (cycles_delay >= (1 << 13) * 256) {
        @compileError("XOSC: Max delay is 0x1fff00 cycles");
    }

    xosc.startup.modify(.{
        .delay = cycles_delay / 256,
    });

    xosc.ctrl.modify(.{
        .freq_range = pico.XOSC_CTRL_FREQ_RANGE_VALUE_1_15MHZ,
        .enable = 1,
    });

    while (xosc.status.read().stable != 1) {}
}

pub fn waitCycles(cycles: u8) void {
    xosc.count.write(cycles);
    while (xosc.count.read() != 0) {}
}


//
// Registers
//

const xosc: mmio.RegisterList(pico.XOSC_BASE, &.{
    .{ .name = "ctrl", .type = packed struct {
        freq_range: u12,
        enable: u12,
        _pad: u8,
    }},

    .{ .name = "status", .type = packed struct {
        freq_range: u2,
        _reserved0: u10,
        enabled: u1,
        _reserved1: u11,
        badwrite: u1,
        _reserved2: u6,
        stable: u1,
    }},

    .{ .name = "dormant", .type = u32 },

    .{ .name = "startup", .type = packed struct {
        delay: u14,
        _reserved0: u6,
        x4: u1,
        _reserved1: u11,
    }},

    .{ .name = "count", .type = u32 },
}) = .{};
