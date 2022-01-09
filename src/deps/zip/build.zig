const builtin = @import("builtin");
const std = @import("std");
const Builder = std.build.Builder;

pub fn linkArtifact(b: *Builder, exe: *std.build.LibExeObjStep, target: std.zig.CrossTarget, comptime prefix_path: []const u8) void {
    _ = b;
    _ = target;
    exe.linkLibC();
    
    exe.addIncludeDir(prefix_path ++ "src/deps/zip/zip/src");
    const c_flags = if (builtin.target.os.tag == .macos) [_][]const u8{ "-std=c99", "-ObjC", "-fobjc-arc" } else [_][]const u8{"-std=c99", "-fno-sanitize=undefined" };
    exe.addCSourceFile(prefix_path ++ "src/deps/zip/zip/src/zip.c", &c_flags);
}



