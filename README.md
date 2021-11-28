# Zig running on a Pico

A playground for Zig running on a RPi Pico.

At first I was trying to get the pico-sdk working with Zig but that seems to be
quite the challeng as it is not even compatible with clang yet. I might combine
some parts of the SDK, the 'hardware', register and bootloader parts.

Right now it only runs from RAM, no QSPI flash support (boot-stage2) has been
implemented yet.

Blinky LED :D

## Notes

- All peripherals are put in 'reset' state after a hard reset. You cannot write
  to their registers while in the reset state. First set the 'RESETS' register
  to enable the peripherals you need.
  (This took wayyy too long to figure out...)