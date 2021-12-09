const xosc = @import("xosc.zig");
const mmio = @import("mmio.zig");
const pico = @import("pico.zig");
const pll = @import("pll.zig");

const Clock = enum {
    gpout0,
    gpout1,
    gpout2,
    gpout3,
    ref,
    sys,
    peri,
    usb,
    adc,
    rtc,
};

pub fn init() void {
    // Disable resus for sys clock
    clock_regs.sys_resus_ctrl.write(0);

    xosc.init(pico.XOSC_MHZ * 1_000_000 / 1000);

    // Switch both sys and ref away from aux clocks before touchting PLLs
    clock_regs.sys_ctrl.modify(.{
        .src = 0,
    });
    while (clock_regs.sys_selected.read() != 1) {}

    clock_regs.ref_ctrl.modify(.{
        .src = 0,
    });
    while (clock_regs.ref_selected.read() != 1) {}

    // The PLL configuration below is taken directly from the pico-sdk
    // Configure PLLs
    //                   REF     FBDIV VCO            POSTDIV
    // PLL SYS: 12 / 1 = 12MHz * 125 = 1500MHZ / 6 / 2 = 125MHz
    // PLL USB: 12 / 1 = 12MHz * 40  = 480 MHz / 5 / 2 =  48MHz
    pll.init(.sys, 1, 1500_000_000, 6, 2);
    pll.init(.usb, 1, 480_000_000, 5, 2);
    // TODO: Would be cool to have the functionality of the 'vcocalc.py' script
    // built into here as comptime.

    configure(.ref, .{
        .src = 0x2,
        .src_freq = pico.XOSC_MHZ * 1_000_000,
        .freq = pico.XOSC_MHZ * 1_000_000,
    });

    configure(.sys, .{
        .src = 0x1,    // aux
        .auxsrc = 0x0, // pll_sys
        .src_freq = 125_000_000,
        .freq = 125_000_000,
    });

    configure(.peri, .{
        .auxsrc = 0x0, // pll_sys
        .src_freq = 125_000_000,
        .freq = 125_000_000,
    });

    //configure(.usb, .{
    //    .auxsrc = 0x0, // pll_usb
    //    .src_freq = 48_000_000,
    //    .freq = 48_000_000,
    //});

    configure(.adc, .{
        .auxsrc = 0x0, // pll_usb
        .src_freq = 48_000_000,
        .freq = 48_000_000,
    });

    configure(.rtc, .{
        .auxsrc = 0x0, // pll_usb
        .src_freq = 48_000_000,
        .freq = 46875,
    });
}

const ClockConf = struct {
    src: ?u2 = null,
    auxsrc: ?u3 = null,
    src_freq: u32,
    freq: u32,
};

fn configure(comptime clock: Clock, comptime conf: ClockConf) void {
    if (conf.freq > conf.src_freq)
        @compileError("Desired frequency cannot be higher than the source frequency");

    if ((clock != .sys and clock != .ref) and (conf.src != null))
        @compileError("This clock does not have a glitchless src");

    // Div reg is a fixed-point number (24.8)
    const div: u32 = (@as(u64, conf.src_freq) << 8) / conf.freq;

    const ctrl = @field(clock_regs, @tagName(clock) ++ "_ctrl");
    const selected = @field(clock_regs, @tagName(clock) ++ "_selected");

    // Disable clock, or set it to base glitchess clock
    switch (clock) {
        // Glitchless
        .ref, .sys => {
            ctrl.modify(.{
                .src = 0,
            });

            while (selected.read() != 1) {}
        },

        // The rest
        else => {
            ctrl.modify(.{
                .enable = 0,
            });

            // Wait for 3 cycles of the target clock speed for the clock to
            // propagate
            // TODO: This is hacky and hard-coded. The SDK keeps track of the
            // configured frequencies and delays for an actual 3 cycles of the
            // destination clock frequency.
            const cycles: u32 = (125_000_000 / 46875 * 3) / 3;
            asm volatile (
                \\1:
                \\subs r0, #1
                \\bne 1b
                :: [_] "{r0}" (cycles)
                : "r0");
        },
    }

    // Set aux src if specified
    if (conf.auxsrc) |auxsrc| {
        ctrl.modify(.{
            .auxsrc = auxsrc,
        });
    }

    // Set glitchless src if specified, and wait till it has switched
    if (conf.src) |src| {
        ctrl.modify(.{
            .src = src,
        });

        while (selected.read() != (@as(u32, 1) << src)) {}
    }

    // Enable clock again (only does something on aux clocks)
    ctrl.modify(.{
        .enable = 1,
    });

    // Set divider
    @field(clock_regs, @tagName(clock) ++ "_div").write(div);
}

//
// Registers
//

const Ctrl = packed struct {
    src: u2,
    _reserved0: u3,
    auxsrc: u4,
    _reserved1: u1,
    kill: u1,
    enable: u1,
    dc50: u1,
    _reserved2: u3,
    phase: u2,
    _reserved3: u2,
    nudge: u1,
    _reserved4: u11,
};

const clock_regs: mmio.RegisterList(pico.CLOCKS_BASE, &.{
    .{ .name = "gpout0_ctrl", .type = Ctrl },
    .{ .name = "gpout0_div", .type = u32 },
    .{ .name = "gpout0_selected", .type = u32 },
    .{ .name = "gpout1_ctrl", .type = Ctrl },
    .{ .name = "gpout1_div", .type = u32 },
    .{ .name = "gpout1_selected", .type = u32 },
    .{ .name = "gpout2_ctrl", .type = Ctrl },
    .{ .name = "gpout2_div", .type = u32 },
    .{ .name = "gpout2_selected", .type = u32 },
    .{ .name = "gpout3_ctrl", .type = Ctrl },
    .{ .name = "gpout3_div", .type = u32 },
    .{ .name = "gpout3_selected", .type = u32 },
    .{ .name = "ref_ctrl", .type = Ctrl },
    .{ .name = "ref_div", .type = u32 },
    .{ .name = "ref_selected", .type = u32 },
    .{ .name = "sys_ctrl", .type = Ctrl },
    .{ .name = "sys_div", .type = u32 },
    .{ .name = "sys_selected", .type = u32 },
    .{ .name = "peri_ctrl", .type = Ctrl },
    .{ .name = "peri_div", .type = u32 },
    .{ .name = "peri_selected", .type = u32 },
    .{ .name = "usb_ctrl", .type = Ctrl },
    .{ .name = "usb_div", .type = u32 },
    .{ .name = "usb_selected", .type = u32 },
    .{ .name = "adc_ctrl", .type = Ctrl },
    .{ .name = "adc_div", .type = u32 },
    .{ .name = "adc_selected", .type = u32 },
    .{ .name = "rtc_ctrl", .type = Ctrl },
    .{ .name = "rtc_div", .type = u32 },
    .{ .name = "rtc_selected", .type = u32 },

    .{ .name = "sys_resus_ctrl", .type = u32 },
    .{ .name = "sys_resus_status", .type = u32 },

    .{ .name = "fc0_ref_khz", .type = u32 },
    .{ .name = "fc0_min_khz", .type = u32 },
    .{ .name = "fc0_max_khz", .type = u32 },
    .{ .name = "fc0_delay", .type = u32 },
    .{ .name = "fc0_interval", .type = u32 },
    .{ .name = "fc0_src", .type = u32 },
    .{ .name = "fc0_status", .type = u32 },
    .{ .name = "fc0_result", .type = u32 },

    .{ .name = "wake_en0", .type = u32 },
    .{ .name = "wake_en1", .type = u32 },
    .{ .name = "sleep_en0", .type = u32 },
    .{ .name = "sleep_en1", .type = u32 },
    .{ .name = "enabled0", .type = u32 },
    .{ .name = "enabled1", .type = u32 },

    .{ .name = "intr", .type = u32 },
    .{ .name = "inte", .type = u32 },
    .{ .name = "intf", .type = u32 },
    .{ .name = "ints", .type = u32 },
}) = .{};
