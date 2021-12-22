const std = @import("std");
const upaya = @import("upaya.zig");
const sokol = upaya.sokol;

pub const RenderTexture = extern struct {
    img: sokol.gfx.sg_image = undefined,
    width: i32 = 0,
    height: i32 = 0,

    pub const Filter = enum { linear, nearest };

    pub fn init(width: i32, height: i32, filter: Filter) RenderTexture {
        var img_desc = std.mem.zeroes(sokol.gfx.sg_image_desc);
        img_desc.render_target = true;
        img_desc.width = width;
        img_desc.height = height;
        img_desc.pixel_format = .SG_PIXELFORMAT_RGBA8;
        img_desc.min_filter = if (filter == .linear) .SG_FILTER_LINEAR else .SG_FILTER_NEAREST;
        img_desc.mag_filter = if (filter == .linear) .SG_FILTER_LINEAR else .SG_FILTER_NEAREST;

        return .{ .width = width, .height = height, .img = upaya.sokol.gfx.sg_make_image(&img_desc) };
    }

    pub fn deinit(self: RenderTexture) void {
        sokol.gfx.sg_destroy_image(self.img);
    }

    pub fn imTextureID(self: RenderTexture) upaya.imgui.ImTextureID {
        return @intToPtr(*c_void, self.img.id);
    }
};
