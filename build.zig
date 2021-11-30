const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = std.zig.CrossTarget{
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m0plus },
        .os_tag = .freestanding,
        .abi = .eabi,
    };

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("zig-blink", "src/crt0.zig");
    //exe.addAssemblyFile("src/crt0.S");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addSystemIncludeDir("inc");
    exe.setLinkerScriptPath("simple.ld");
    exe.install();

    const uf2_cmd = b.addSystemCommand(&.{"elf2uf2"});
    uf2_cmd.addArtifactArg(exe);
    uf2_cmd.addArg("zig-out/bin/zig-blink.uf2");

    const uf2 = b.step("uf2", "Build program and convert to uf2");
    uf2.dependOn(&uf2_cmd.step);

    const flash_cmd = b.addSystemCommand(&.{"picotool", "load", "-x", "zig-out/bin/zig-blink.uf2"});

    const flash = b.step("flash", "Build and flash to Pico. This requires picotool, and udev rules to set permissions for Pico devices");
    flash.dependOn(uf2);
    flash.dependOn(&flash_cmd.step);
}
