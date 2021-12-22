const builtin = @import("builtin");
const std = @import("std");
const Builder = std.build.Builder;

pub fn linkArtifact(b: *Builder, exe: *std.build.LibExeObjStep, target: std.zig.CrossTarget, comptime prefix_path: []const u8) void {
    exe.linkLibC();

    if (target.isDarwin()) {
        addMacosSdkDirs(b, target, exe) catch unreachable;
        exe.linkFramework("Foundation");
        exe.linkFramework("Cocoa");
        exe.linkFramework("Quartz");
        exe.linkFramework("QuartzCore");
        exe.linkFramework("Metal");
        exe.linkFramework("MetalKit");
        exe.linkFramework("OpenGL");
        exe.linkFramework("Audiotoolbox");
        exe.linkFramework("CoreAudio");
        exe.linkSystemLibrary("c++");
    } else if (target.isLinux()) {
        exe.linkSystemLibrary("GL");
        exe.linkSystemLibrary("GLEW");
        exe.linkSystemLibrary("X11");
    }

    exe.addIncludeDir(prefix_path ++ "src/deps/sokol/sokol");
    exe.addIncludeDir(prefix_path ++ "src/deps/sokol/sokol/util");
    const c_flags = if (builtin.target.os.tag == .macos) [_][]const u8{ "-std=c99", "-ObjC", "-fobjc-arc" } else [_][]const u8{"-std=c99"};
    exe.addCSourceFile(prefix_path ++ "src/deps/sokol/compile_sokol.c", &c_flags);
}

/// macOS helper function to add SDK search paths
fn addMacosSdkDirs(b: *Builder, target: std.zig.CrossTarget, step: *std.build.LibExeObjStep) !void {
    const sdk_dir = std.zig.system.darwin.getDarwinSDK(b.allocator, target.toTarget());


    if (sdk_dir) |dir| {
        const framework_dir = try std.mem.concat(b.allocator, u8, &[_][]const u8{ dir.path, "/System/Library/Frameworks" });
        step.addFrameworkDir(framework_dir);
    }

}
