const std = @import("std");

const app = @cImport(@cInclude("sokol_app.h"));
const gfx = @cImport(@cInclude("sokol_gfx.h"));
const glue = @cImport(@cInclude("sokol_glue.h"));
const imgui = @cImport(@cInclude("sokol_imgui.h"));

pub fn main() !void {
     std.log.warn("sokol_app {}", .{app});
    std.log.warn("sokol_gfx {}", .{gfx});
    std.log.warn("sokol_glue {}", .{glue});
     std.log.warn("sokol_imgui {}", .{imgui});
 }