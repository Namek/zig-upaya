const std = @import("std");
const upaya = @import("upaya_cli.zig");
const Texture = @import("texture.zig").Texture;
const Point = @import("math/point.zig").Point;

/// Image is a CPU side array of color data with some helper methods that can be used to prep data
/// before creating a Texture
pub const Image = struct {
    w: usize = 0,
    h: usize = 0,
    pixels: []u32,

    pub fn init(width: usize, height: usize) Image {
        return .{ .w = width, .h = height, .pixels = upaya.mem.allocator.alloc(u32, width * height) catch unreachable };
    }

    pub fn initFromFile(file: []const u8) Image {
        const image_contents = upaya.fs.read(upaya.mem.tmp_allocator, file) catch unreachable;

        var w: c_int = undefined;
        var h: c_int = undefined;
        var channels: c_int = undefined;
        const load_res = upaya.stb.stbi_load_from_memory(image_contents.ptr, @intCast(c_int, image_contents.len), &w, &h, &channels, 4);
        if (load_res == null) unreachable;
        defer upaya.stb.stbi_image_free(load_res);

        var img = init(@intCast(usize, w), @intCast(usize, h));
        var pixels = std.mem.bytesAsSlice(u32, load_res[0..@intCast(usize, w * h * channels)]);
        for (pixels) |p, i| {
            img.pixels[i] = p;
        }

        return img;
    }

    pub fn initFromData(data: [*c]const u8, len: u64) Image {
        var w: c_int = undefined;
        var h: c_int = undefined;
        var channels: c_int = undefined;
        const load_res = upaya.stb.stbi_load_from_memory(data, @intCast(c_int, len), &w, &h, &channels, 4);
        if (load_res == null) {
            std.debug.print("null image!\n", .{});
            unreachable;
        }

        defer upaya.stb.stbi_image_free(load_res);

        var img = init(@intCast(usize, w), @intCast(usize, h));
        var pixels = std.mem.bytesAsSlice(u32, load_res[0..@intCast(usize, w * h * channels)]);
        for (pixels) |p, i| {
            img.pixels[i] = p;
        }

        return img;
    }

    pub fn deinit(self: Image) void {
        upaya.mem.allocator.free(self.pixels);
    }

    pub fn fillRect(self: *Image, rect: upaya.math.Rect, color: upaya.math.Color) void {
        const x = @intCast(usize, rect.x);
        var y = @intCast(usize, rect.y);
        const w = @intCast(usize, rect.width);
        var h = @intCast(usize, rect.height);

        var data = self.pixels[x + y * self.w ..];
        while (h > 0) : (h -= 1) {
            var i: usize = 0;
            while (i < w) : (i += 1) {
                data[i] = color.value;
            }

            y += 1;
            data = self.pixels[x + y * self.w ..];
        }
    }

    pub fn blit(self: *Image, src: Image, x: usize, y: usize) void {
        var yy = y;
        var h = src.h;

        var data = self.pixels[x + yy * self.w ..];
        var src_y: usize = 0;
        while (h > 0) : (h -= 1) {
            data = self.pixels[x + yy * self.w ..];
            const src_row = src.pixels[src_y * src.w .. (src_y * src.w) + src.w];
            std.mem.copy(u32, data, src_row);
            // next row and move our slice to it as well
            src_y += 1;
            yy += 1;
        }
    }

    pub fn blitWithoutTransparent (self: *Image, src: Image, x: usize, y: usize) void {
        var yy = y;
        var h = src.h;

        var data = self.pixels[x + yy * self.w ..];
        var src_y: usize = 0;
        while (h > 0) : (h -= 1) {
            data = self.pixels[x + yy * self.w ..];
            const src_row = src.pixels[src_y * src.w .. (src_y * src.w) + src.w];
            var xx: usize = 0;
            while (xx < src_row.len) : (xx += 1) {
                if (src_row[xx] != 0x00000000)
                    data[xx] = src_row[xx];
            }
            // next row and move our slice to it as well
            src_y += 1;
            yy += 1;
        }

    }

    pub fn asTexture(self: Image, filter: Texture.Filter) Texture {
        return Texture.initWithColorData(self.pixels, @intCast(i32, self.w), @intCast(i32, self.h), filter, .clamp);
    }

    pub fn save(self: Image, file: []const u8) void {
        var c_file = std.cstr.addNullByte(upaya.mem.tmp_allocator, file) catch unreachable;
        var bytes = std.mem.sliceAsBytes(self.pixels);
        _ = upaya.stb.stbi_write_png(c_file.ptr, @intCast(c_int, self.w), @intCast(c_int, self.h), 4, bytes.ptr, @intCast(c_int, self.w * 4));
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

    pub fn crop(self: *Image) Point {
        var top: usize = 0;
        var bottom = self.h - 1;
        var left: usize = 0;
        var right = self.w - 1;

        top: {
            while (top < bottom) : (top += 1) {
                var row = self.pixels[top * self.w .. top * self.w + self.w];
                if (containsColor(row)) {
                    top -= 1;

                    break :top;
                }
            }
        }

        bottom: {
            while (bottom > top) : (bottom -= 1) {
                var row = self.pixels[bottom * self.w - self.w .. bottom * self.w];
                if (containsColor(row)) {
                    break :bottom;
                }
            }
        }

        var v_crop_image = Image.init(self.w, bottom - top);
        std.mem.copy(u32, v_crop_image.pixels, self.pixels[top * self.w .. bottom * self.w]);

        left: {
            while (left < right) : (left += 1) {
                var y: usize = bottom;
                while (y > top) : (y -= 1) {
                    if (self.pixels[left + y * self.w] & 0xFF000000 != 0) {
                        left -= 1;
                        break :left;
                    }
                }
            }
        }

        right: {
            while (right > left) : (right -= 1) {
                var y: usize = bottom;
                while (y > top) : (y -= 1) {
                    if (self.pixels[right + y * self.w] & 0xFF000000 != 0) {
                        right += 1;
                        break :right;
                    }
                }    
            }
        }

        var crop_image = Image.init(right - left, bottom - top);

        var h: usize = crop_image.h;
        while (h > 0) : (h -= 1) {
            const row = v_crop_image.pixels[h * v_crop_image.w - v_crop_image.w .. h * v_crop_image.w];
            const src = row[left..right];
            const dst = crop_image.pixels[h * crop_image.w - crop_image.w .. h * crop_image.w];
            std.mem.copy(u32, dst, src);
        }

        self.h = crop_image.h;
        self.w = crop_image.w;

        std.mem.copy(u32, self.pixels, crop_image.pixels);
        v_crop_image.deinit();
        crop_image.deinit();

        return .{ .x = @intCast(i32, left), .y = @intCast(i32, top) };
    }

    fn containsColor(pixels: []u32) bool {
        for (pixels) |p| {
            if (p & 0xFF000000 != 0) {
                return true;
            }
        }

        return false;
    }
};
