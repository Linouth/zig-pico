# Zig running on a Pico

A playground for Zig running on a Pico (the RP2040 chip).

At first I was trying to get the pico-sdk working with Zig but that seems to be
quite the challenge as it is not even compatible with clang yet. I might combine
some parts of the SDK, the 'hardware', register and bootloader parts.

Right now it only runs from RAM, no QSPI flash support (boot-stage2) has been
implemented yet.

Blinky LED :D

## Progress

### Systems and Peripherals

Following are systems and peripherals taken from the datasheet. 

- SIO
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
    - [ ] XOSC
    - [ ] ROSC
- [ ] PLL
- [ ] GPIO
    - [x] Manual read and writes
    - [ ] Interrupts
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

### General TODOs

Some general TODOs. There are more TODOs sprinkled throughout the code.

- [ ] Figure out how to use the set of functions provided in the Bootrom.
  (float and double operations, memory operations, and more)
- [ ] Find a way to determine at compile time which modules are used, and add
  initialization code for these modules to the reset sequence.
- [ ] Implement error handler in `crt0.zig`
- [ ] Add a boot-stage2 bootloader

## Notes

- All peripherals are put in 'reset' state after a hard reset. You cannot write
  to their registers while in the reset state. First set the 'RESETS' register
  to enable the peripherals you need.
  (This took too long to figure out...)
