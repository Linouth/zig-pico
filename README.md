# zig-pico - RP2040/Pico SDK for Zig

This framework is for writing zig applications for the Pico microcontroller
(RP2040). It is far from finished but can be a great starting point for your own
projects. The project is in active development so anyting can change still. Any
help would also be appreciated.

Right now it only runs from RAM, no QSPI flash support (boot-stage2) has been
implemented yet.

## Usage
Currently you can build your own application by using a `build.zig` file like~
```
const std = @import("std");
const pico = @import("libs/zig-pico/build.zig");

pub fn build(b: *std.build.Builder) !void {
    const mode = b.standardReleaseOptions();

    const pico_exe = pico.PicoExe.init(b, "myproject", "src/main.zig");
    const exe = pico_exe.exe;
    exe.setBuildMode(mode);
    exe.install();
}
```
For flashing you have to convert the elf file to a uf2 file manually (with the
uf2 tool from the pico-sdk repo) and copy it to the pico mass storage drive. You
could also use the picoboot tool for flashing.

Currently I mostly use a gdb session with the swd interface for flashing.

In the future this will be done with the zig build system itself.

## Progress

### Systems and Peripherals

Following are systems and peripherals taken from the datasheet. 

- [ ] SIO
    - [ ] Spinlocks
    - [ ] Integer dividers
    - [ ] Interpolators
    - [ ] FIFOs
- [ ] SysTick Timer
- [ ] MPU
- [x] NVIC
- [ ] DMA
- [ ] Core Supply Regulator
- [ ] Power Control
- [ ] Chip-Level Reset
- [ ] Power-On State Machine
- [x] Subsystem Resets
- [ ] Clocks
    - [x] XOSC
    - [ ] ROSC
- [x] PLL ❕
- [x] GPIO ❕
    - [x] Manual read and writes
    - [x] Interrupts
- [ ] PIO
- [ ] USB
- [ ] UART
- [ ] I2C
- [ ] SPI
- [ ] PWM
- [x] Timer
- [ ] RTC
- [ ] ADC and Temperatue Sensor
- [ ] SSI

Peripherals marked with ❕ are working, but could use some improvements.

### General TODOs

Some general TODOs. There are more TODOs sprinkled throughout the code.

- [ ] Figure out how to use the set of functions provided in the Bootrom.
  (float and double operations, memory operations, and more).
- [ ] Find a way to determine at compile time which modules are used, and add
  initialization code for these modules to the reset sequence.
- [ ] Implement error handler in `crt0.zig`
- [ ] Add a boot-stage2 bootloader.
- [ ] Add on demand compilation (and caching) for the picoboot, pioasm and uf2
  tools in the pico-sdk.

## Notes

- All peripherals are put in 'reset' state after a hard reset. You cannot write
  to their registers while in the reset state. First set the 'RESETS' register
  to enable the peripherals you need.
