const std = @import("std");

const c = @cImport(@cInclude("zip.h"));

pub fn main() !void {
     std.log.warn("zip {}", .{c});
 }