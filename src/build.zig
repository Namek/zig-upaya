const builtin = @import("builtin");
const std = @import("std");
const Builder = std.build.Builder;
const Pkg = std.build.Pkg;

const sokol_build = @import("deps/sokol/build.zig");
const stb_build = @import("deps/stb/build.zig");
const imgui_build = @import("deps/imgui/build.zig");
const filebrowser_build = @import("deps/filebrowser/build.zig");
const zip_build = @import("deps/zip/build.zig");

pub fn linkArtifact(b: *Builder, artifact: *std.build.LibExeObjStep, target: std.zig.CrossTarget, comptime prefix_path: []const u8) void {
    sokol_build.linkArtifact(b, artifact, target, prefix_path);
    stb_build.linkArtifact(b, artifact, target, prefix_path);
    imgui_build.linkArtifact(b, artifact, target, prefix_path);
    filebrowser_build.linkArtifact(b, artifact, target, prefix_path);
    zip_build.linkArtifact(b, artifact, target, prefix_path);

    const sokol = Pkg{
        .name = "sokol",
        .path = .{.path=prefix_path ++ "src/deps/sokol/sokol.zig"},
    };
    const stb = Pkg{
        .name = "stb",
        .path = .{.path=prefix_path ++ "src/deps/stb/stb.zig"},
    };
    const imgui = Pkg{
        .name = "imgui",
        .path = .{.path=prefix_path ++ "src/deps/imgui/imgui.zig"},
    };
    const filebrowser = Pkg{
        .name = "filebrowser",
        .path = .{.path=prefix_path ++ "src/deps/filebrowser/filebrowser.zig"},
    };
    const zip = Pkg{
        .name = "zip",
        .path = .{.path=prefix_path ++ "src/deps/zip/zip.zig"},
    };
    const upaya = Pkg{
        .name = "upaya",
        .path = .{.path=prefix_path ++ "src/upaya.zig"},
        .dependencies = &[_]Pkg{ stb, filebrowser, sokol, imgui },
    };

    // packages exported to userland
    artifact.addPackage(upaya);
    artifact.addPackage(sokol);
    artifact.addPackage(stb);
    artifact.addPackage(imgui);
    artifact.addPackage(filebrowser);
    artifact.addPackage(zip);
}

pub fn linkCommandLineArtifact(b: *Builder, artifact: *std.build.LibExeObjStep, target: std.build.Target, comptime prefix_path: []const u8) void {
    stb_build.linkArtifact(b, artifact, target, prefix_path);
    zip_build.linkArtifact(b, artifact, target, prefix_path);

    const stb = Pkg{
        .name = "stb",
        .path = prefix_path ++ "src/deps/stb/stb.zig",
    };
    const upaya = Pkg{
        .name = "upaya",
        .path = prefix_path ++ "src/upaya_cli.zig",
        .dependencies = &[_]Pkg{stb},
    };
    const zip = Pkg{
        .name = "zip",
        .path = prefix_path ++ "src/deps/zip/zip.zig",
    };

    // packages exported to userland
    artifact.addPackage(upaya);
    artifact.addPackage(stb);
    artifact.addPackage(zip);

}

// add tests.zig file runnable via "zig build test"
pub fn addTests(b: *Builder, target: std.build.Target) void {
    var tst = b.addTest("src/tests.zig");
    linkArtifact(b, tst, target, "");
    const test_step = b.step("test", "Run tests in tests.zig");
    test_step.dependOn(&tst.step);
}
