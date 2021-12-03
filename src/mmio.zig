const std = @import("std");

/// Heavily inspired by https://github.com/lynaghk/svd2zig
pub fn Reg(comptime Fields: type) type {
    if (@sizeOf(Fields) != 4)
        @compileError("Fields type has to be 'u32' in size");

    return struct {
        raw_ptr: *volatile u32,

        const Self = @This();

        pub fn init(addr: u32) Self {
            return Self { .raw_ptr = @intToPtr(*volatile u32, addr) };
        }

        pub fn initMultiple(start_addr: u32, comptime count: usize, comptime offset: usize) [count]Self {
            var regs: [count]Self = undefined;
            var i: usize = 0;
            inline while (i < count) : (i += 1) {
                regs[i] = Self.init(start_addr + (i*offset));
            }
            return regs;
        }

        pub fn read(self: Self) Fields {
            return @bitCast(Fields, self.raw_ptr.*);
        }

        pub fn write(self: Self, val: Fields) void {
            self.raw_ptr.* = @bitCast(u32, val);
        }

        pub fn modify(self: Self, new: anytype) void {
            //@compileLog("Type of new: ", @typeInfo(@TypeOf(new)).Struct.fields[0].field_type);
            var curr = self.read();
            const info = @typeInfo(@TypeOf(new));

            switch (@typeInfo(Fields)) {
                .Struct => {
                    inline for (info.Struct.fields) |field| {
                        @field(curr, field.name) = @field(new, field.name);
                    }
                    self.write(curr);
                },
                //.Int => {
                //    const format = "Expecting argument of the following format: .{ .And = 12345 }";
                //    if (info.Struct.fields.len != 1)
                //        @compileError(format); 

                //    const name = info.Struct.fields[0].name;
                //    const val = @field(new, name);
                //    const old = self.read();

                //    if (std.mem.eql(u8, name, "And")) {
                //        self.write(old & val);
                //    } else if (std.mem.eql(u8, name, "Or")) {
                //        self.write(old | val);
                //    } else {
                //        @compileError(format);
                //    }
                //},
                else => {
                    @compileError("Cannot 'modify' Register with Fields type as '" ++ @typeName(Fields) ++ "'");
                },
            }
        }

        // TODO: Implement these bitwise operations in 'modify'
        pub fn bitOr(self: Self, val: u32) void {
            if (@typeInfo(Fields) != .Int)
                @compileError("Can only 'bitOr' Register with Fields type 'Int'");

            self.raw_ptr.* |= val;
        }

        pub fn bitAnd(self: Self, val: u32) void {
            if (@typeInfo(Fields) != .Int)
                @compileError("Can only 'bitAnd' Register with Fields type 'Int'");

            self.raw_ptr.* &= val;
        }
    };
}

pub const Reg32 = Reg(u32);


pub const RegConfig = struct {
    name: []const u8,
    type: type,
};

const TypeInfo = std.builtin.TypeInfo;

// Sigh... Aparently creating a new struct with decls is not allowed...
// (#6709)
pub fn RegisterListUnsupported(comptime entries: []const RegConfig) type {
    var decs: [128]TypeInfo.Declaration = undefined;
    inline for (entries) |entry, i| {
        decs[i] = .{
            .name = entry.name,
            .is_pub = false,
            .data = .{
                .Var = Register(entry.type),
            },
        };
    }

    const info = TypeInfo{
        .Struct = .{
            .layout = .Auto,
            .fields = &.{},
            .decls = decs[0..entries.len],
            .is_tuple = false,
        }
    };

    return @Type(info);
}

// Shitty workaround using fields instead of decls...
// You need to initiate the const with default values.
pub fn RegisterList(comptime start_addr: u32, comptime entries: []const RegConfig) type {
    var fields: [entries.len]TypeInfo.StructField = undefined;
    inline for (entries) |entry, i| {
        fields[i] = .{
            .name = entry.name,
            .field_type = Reg(entry.type),
            .default_value = Reg(entry.type).init(start_addr + i*4),
            .is_comptime = true,
            .alignment = 1,
        };
    }

    const info = TypeInfo{
        .Struct = .{
            .layout = .Auto,
            .fields = fields[0..entries.len],
            .decls = &.{},
            .is_tuple = false,
        }
    };

    return @Type(info);
}
