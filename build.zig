const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const mode = b.standardReleaseOptions();

    const pico_exe = PicoExe.init(b, "zig-blink", "app/main.zig");
    //try pico_exe.addPioSource(.{ .name = "pwm", .file = "pwm.pio" });

    const exe = pico_exe.exe;
    exe.setBuildMode(mode);
    exe.install();

    // TODO: Implement uf2 generation and flashing with picotool. End goal would
    // be to compile and cache the tools when they are needed.

    //const uf2_cmd = b.addSystemCommand(&.{"elf2uf2"});
    //uf2_cmd.addArtifactArg(exe);
    //uf2_cmd.addArg("zig-out/bin/zig-blink.uf2");

    //const uf2 = b.step("uf2", "Build program and convert to uf2");
    //uf2.dependOn(&uf2_cmd.step);

    //const flash_cmd = b.addSystemCommand(&.{"picotool", "load", "-x", "zig-out/bin/zig-blink.uf2"});

    //const flash = b.step("flash", "Build and flash to Pico. This requires picotool, and udev rules to set permissions for Pico devices");
    //flash.dependOn(uf2);
    //flash.dependOn(&flash_cmd.step);
}

const PioSource = struct {
    name: []const u8,
    file: []const u8,
};

pub const PicoExe = struct {
    exe: *std.build.LibExeObjStep,
    pio_step: *std.build.OptionsStep,

    pub fn init(
        builder: *std.build.Builder,
        name: []const u8,
        app_src: []const u8
    ) PicoExe {
        const target = std.zig.CrossTarget{
            .cpu_arch = .thumb,
            .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m0plus },
            .os_tag = .freestanding,
            .abi = .eabi,
        };

        // The zig-pico sdk package used by the user application.
        const pico = std.build.Pkg{
            .name = "pico",
            .path = .{ .path = "src/pico.zig" },
        };

        // The generated bytecode for the PIO peripheral
        const pio_step = builder.addOptions();
        const pio = std.build.Pkg{
            .name = "pio-bytecode",
            .path = .{ .generated = &pio_step.generated_file },
        };

        // The user applcation
        const app = std.build.Pkg{
            .name = "app",
            .path = .{ .path = app_src },
            .dependencies = &.{ pico, pio },
        };

        const exe = builder.addExecutable(name, "src/crt0.zig");
        exe.single_threaded = true;
        exe.setTarget(target);
        exe.setLinkerScriptPath(.{ .path = "simple.ld" });
        exe.addPackage(app);

        return PicoExe{
            .exe = exe,
            .pio_step = pio_step,
        };
    }

    pub fn addPioSource(self: PicoExe, source: PioSource) !void {
        const program = try pioasm(self.exe.builder.allocator, source.file);
        defer self.exe.builder.allocator.free(program);

        self.pio_step.addOption([]const u16, source.name, program);
    }

    pub fn addPioSources(self: PicoExe, sources: []const PioSource) !void {
        for (sources) |source| {
            try self.addPioSource(source);
        }
    }
};

// TODO: Add the pioc-sdk tools dir as a dependency and compile and cache the
// pioasm tool and use that instead of a system wide installed verison.
// TODO: See if compilation of the pio files can be done as a step, with the
// result cached if there are no changes.
fn pioasm(alloc: std.mem.Allocator, file: []const u8) ![]u16 {
    const child = std.ChildProcess.init(&.{
        "pioasm",
        "-o",
        "hex",
        file
    }, alloc) catch unreachable;
    defer child.deinit();

    //child.cwd = exe.builder.build_root;
    //child.env_map = self.builder.env_map;

    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;

    child.spawn() catch |err| {
        std.debug.print("Unable to spawn pioasm: {s}\n", .{ @errorName(err) });
        return err;
    };

    var out = std.ArrayList(u16).init(alloc);
    const reader = child.stdout.?.reader();

    var buf: [5]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        const int = try std.fmt.parseInt(u16, line, 16);
        try out.append(int);
    }

    const term = child.wait() catch |err| {
        std.debug.print("Unable to spawn pioasm: {s}\n", .{ @errorName(err) });
        return err;
    };

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("Pioasm exited with error code {}.\n", .{ code });
                return error.PioasmError;
            }
        },
        else => {
            std.debug.print("Pioasm terminated unexpectedly..?\n", .{});
            return error.UncleanExit;
        },
    }

    return out.toOwnedSlice();
}
