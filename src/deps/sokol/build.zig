const builtin = @import("builtin");
const std = @import("std");
const Builder = std.build.Builder;

pub fn build(_: *Builder) void {}

pub fn linkArtifact(b: *Builder, exe: *std.build.LibExeObjStep, target: std.zig.CrossTarget, comptime prefix_path: []const u8) void {
    exe.linkLibC();

    if (target.isDarwin()) {
        addMacosSdkDirs(b, exe) catch unreachable;
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

    exe.addIncludeDir(prefix_path ++ "src/deps/sokol");
    const c_flags = if (builtin.target.os.tag == .macos) [_][]const u8{ "-std=c99", "-ObjC", "-fobjc-arc" } else [_][]const u8{"-std=c99"};
    exe.addCSourceFile(prefix_path ++ "src/deps/sokol/compile_sokol.c", &c_flags);
}

/// macOS helper function to add SDK search paths
fn addMacosSdkDirs(b: *Builder, step: *std.build.LibExeObjStep) !void {
    const sdk = std.zig.system.darwin.getDarwinSDK(b.allocator, builtin.target).?;
    const sdk_dir = sdk.path;
    const framework_dir = try std.mem.concat(b.allocator, u8, &[_][]const u8 { sdk_dir, "/System/Library/Frameworks" });
    // const usrinclude_dir = try std.mem.concat(b.allocator, u8, &[_][]const u8 { sdk_dir, "/usr/include"});
    step.addFrameworkDir(framework_dir);
    // step.addIncludeDir(usrinclude_dir);
}

