const IO_BANK0_BASE: u32 = 0x40014000;
const GP25_STATUS: u32 = 0x0c8;
const GP25_CTRL: u32 = 0x0cc;

const PADS_BANK0_BASE: u32 = 0x4001c000;
const GP25_PAD: u32 = 0x68;

const SIO_BASE: u32 = 0xd0000000;
const GPIO_OUT: u32 = 0x10;
const GPIO_SET: u32 = 0x14;
const GPIO_CLR: u32 = 0x18;
const GPIO_XOR: u32 = 0x1c;
const GPIO_OE: u32 = 0x20;
const GPIO_OE_SET: u32 = 0x24;
const GPIO_OE_CLR: u32 = 0x28;

const RESETS_BASE: u32 = 0x4000c000;

const IoBank0 = packed struct {
    gpio: [29]Gpio,

    const Gpio = packed struct {
        status: u32,
        ctrl: u32,
    };
};

const bank0 = @intToPtr(*IoBank0, IO_BANK0_BASE);

pub fn main() void {
    // Enable IO_BANK0 and PADS_BANK0 peripherals
    const resets = @intToPtr(*u32, RESETS_BASE);
    resets.* ^= (1 << 5) | (1 << 8);


    const gpio_oe_set = @intToPtr(*u32, SIO_BASE + GPIO_OE_SET);
    const gpio_oe_clr = @intToPtr(*u32, SIO_BASE + GPIO_OE_CLR);

    const gpio_set = @intToPtr(*u32, SIO_BASE + GPIO_SET);
    const gpio_clr = @intToPtr(*u32, SIO_BASE + GPIO_CLR);
    const gpio_xor = @intToPtr(*u32, SIO_BASE + GPIO_XOR);

    // Init pin
    gpio_oe_clr.* = 1<<25;
    gpio_clr.* = 1<<25;

    // Set function
    const pad = @intToPtr(*u32, PADS_BANK0_BASE + GP25_PAD);
    pad.* = (0b01)<<6 | (pad.* & 0b00111111);

    bank0.gpio[25].ctrl = 5;

    // Set dir to output
    gpio_oe_set.* = 1<<25;

    while (true) {
        gpio_xor.* = 1<<25;
        busySleep(100_000);
    }
}

fn busySleep(comptime cycles: u32) void {
    const CYCLES = 133_000_000 / 1000;

    var i: u32 = 0;
    while (i < (cycles)) : (i += 1) {
        asm volatile ("nop");
    }
}

