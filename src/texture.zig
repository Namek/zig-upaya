const std = @import("std");
const upaya = @import("upaya.zig");
const sokol = upaya.sokol;

pub const Texture = extern struct {
    img: sokol.sg_image = undefined,
    width: i32 = 0,
    height: i32 = 0,

    pub const Filter = enum { linear, nearest };
    pub const Wrap = enum { clamp, repeat };

    pub fn initOffscreen(width: i32, height: i32, filter: Filter) Texture {
        var img_desc = std.mem.zeroes(sokol.sg_image_desc);
        img_desc.render_target = true;
        img_desc.width = width;
        img_desc.height = height;
        img_desc.pixel_format = .SG_PIXELFORMAT_RGBA8;
        img_desc.min_filter = if (filter == .linear) .SG_FILTER_LINEAR else .SG_FILTER_NEAREST;
        img_desc.mag_filter = if (filter == .linear) .SG_FILTER_LINEAR else .SG_FILTER_NEAREST;

        return .{ .width = width, .height = height, .img = sokol.sg_make_image(&img_desc) };
    }

    pub fn init(width: i32, height: i32, filter: Filter) Texture {
        var img_desc = std.mem.zeroes(sokol.sg_image_desc);
        img_desc.width = width;
        img_desc.height = height;
        img_desc.pixel_format = .SG_PIXELFORMAT_RGBA8;
        img_desc.wrap_u = .SG_WRAP_CLAMP_TO_EDGE;
        img_desc.wrap_v = .SG_WRAP_CLAMP_TO_EDGE;
        img_desc.min_filter = if (filter == .linear) .SG_FILTER_LINEAR else .SG_FILTER_NEAREST;
        img_desc.mag_filter = if (filter == .linear) .SG_FILTER_LINEAR else .SG_FILTER_NEAREST;
        img_desc.content.subimage[0][0].size = width * height * 4 * @sizeOf(u8);

        return .{ .width = width, .height = height, .img = sokol.sg_make_image(&img_desc) };
    }

    pub fn initTransparent(width: i32, height: i32) Texture {
        var img = upaya.Image.init(@intCast(usize, width), @intCast(usize, height));
        img.fillRect(.{ .width = width, .height = height }, upaya.math.Color.transparent);
        return img.asTexture(.nearest);

    }

    pub fn initWithData(pixels: []u8, width: i32, height: i32, filter: Filter) Texture {
        var img_desc = std.mem.zeroes(sokol.sg_image_desc);
        img_desc.width = width;
        img_desc.height = height;
        img_desc.pixel_format = .SG_PIXELFORMAT_RGBA8;
        img_desc.wrap_u = .SG_WRAP_CLAMP_TO_EDGE;
        img_desc.wrap_v = .SG_WRAP_CLAMP_TO_EDGE;
        img_desc.min_filter = if (filter == .linear) .SG_FILTER_LINEAR else .SG_FILTER_NEAREST;
        img_desc.mag_filter = if (filter == .linear) .SG_FILTER_LINEAR else .SG_FILTER_NEAREST;
        img_desc.data.subimage[0][0].ptr = pixels.ptr;
        img_desc.data.subimage[0][0].size = @intCast(usize, width * height * 4 * @sizeOf(u8));
        img_desc.label = "upaya-texture";


        return .{ .width = width, .height = height, .img = sokol.sg_make_image(&img_desc) };
    }

    pub fn initWithColorData(pixels: []u32, width: i32, height: i32, filter: Filter, wrap: Wrap) Texture {
        var img_desc = std.mem.zeroes(sokol.sg_image_desc);
        img_desc.width = width;
        img_desc.height = height;
        img_desc.pixel_format = .SG_PIXELFORMAT_RGBA8;
        img_desc.wrap_u = if (wrap == .clamp) .SG_WRAP_CLAMP_TO_EDGE else .SG_WRAP_REPEAT;
        img_desc.wrap_v = if (wrap == .clamp) .SG_WRAP_CLAMP_TO_EDGE else .SG_WRAP_REPEAT;
        img_desc.min_filter = if (filter == .linear) .SG_FILTER_LINEAR else .SG_FILTER_NEAREST;
        img_desc.mag_filter = if (filter == .linear) .SG_FILTER_LINEAR else .SG_FILTER_NEAREST;
        //img_desc.data.subimage[0][0].ptr = pixels.ptr;
        //img_desc.data.subimage[0][0].size = @intCast(usize, width * height * @sizeOf(u32));
        img_desc.label = "upaya-texture";
        img_desc.usage = .SG_USAGE_DYNAMIC;

        var img = sokol.sg_make_image(&img_desc);

        var img_data: sokol.sg_image_data = std.mem.zeroes(sokol.sg_image_data);
        img_data.subimage[0][0].ptr = pixels.ptr;
        img_data.subimage[0][0].size = @intCast(usize, width * height * @sizeOf(u32));

        sokol.sg_update_image(img, &img_data);

        return .{ .width = width, .height = height, .img = img };
    }

    pub fn initFromFile(file: []const u8, filter: Filter) !Texture {
        const image_contents = try upaya.fs.read(upaya.mem.tmp_allocator, file);

        var w: c_int = undefined;
        var h: c_int = undefined;
        var channels: c_int = undefined;
        const load_res = upaya.stb.stbi_load_from_memory(image_contents.ptr, @intCast(c_int, image_contents.len), &w, &h, &channels, 4);
        if (load_res == null) return error.ImageLoadFailed;
        defer upaya.stb.stbi_image_free(load_res);

        return Texture.initWithData(load_res[0..@intCast(usize, w * h * channels)], w, h, filter);
    }

    pub fn initChecker(width: i32, height: i32, color1: upaya.math.Color, color2: upaya.math.Color) Texture {
        var img = upaya.Image.init(@intCast(usize, width), @intCast(usize, height));
        img.fillRect(.{ .width = width, .height = height }, color1);

        var y: usize = 0;
        while (y < img.h) : (y += 1) {
            var row = img.pixels[y * img.w .. (y * img.w) + img.w];
            for (row) |_, i| {
                if (y % 2 == 0) {
                    if (i % 2 != 0) {
                        row[i] = color2.value;
                    }
                } else {
                    if (i % 2 == 0) {
                        row[i] = color2.value;
                    }

                }
            }
        }
        return img.asTexture(.nearest);
    }

    pub fn deinit(self: Texture) void {
        sokol.sg_destroy_image(self.img);
    }

    pub fn setData(self: Texture, pixels: []u8) void {
        _ = self;
        _ = pixels;
        std.debug.panic("not implemented\n", .{});
        // aya.gfx.device.setTextureData2D(self.tex, .color, 0, 0, self.width, self.height, 0, &data[0], @intCast(i32, data.len));
    }

    pub fn setColorData(self: Texture, pixels: []u32) void {
        //std.debug.panic("not implemented\n", .{});

        var data: sokol.sg_image_data = std.mem.zeroes(sokol.sg_image_data);
        data.subimage[0][0].ptr = pixels.ptr;
        data.subimage[0][0].size = @intCast(usize, self.width * self.height * @sizeOf(u32));      

        sokol.sg_update_image(self.img, &data);
    }

    pub fn imTextureID(self: Texture) upaya.imgui.ImTextureID {
        return @intToPtr(*c_void, self.img.id);
    }

    /// returns true if the image was loaded successfully
    pub fn getTextureSize(file: []const u8, w: *c_int, h: *c_int) bool {
        const image_contents = upaya.fs.read(upaya.mem.tmp_allocator, file) catch unreachable;
        var comp: c_int = undefined;
        if (upaya.stb.stbi_info_from_memory(image_contents.ptr, @intCast(c_int, image_contents.len), w, h, &comp) == 1) {
            return true;
        }

        return false;
    }
};
