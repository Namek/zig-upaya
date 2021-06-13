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
            const src_row = src.pixels[src_y * src.w .. (src_y * src.w) + src.w];
            std.mem.copy(u32, data, src_row);

            // next row and move our slice to it as well
            src_y += 1;
            yy += 1;
            data = self.pixels[x + yy * self.w ..];
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

    /// crops image and returns the origin offset of the new image
    pub fn crop(self: *Image) Point {
        const padding: usize = 1;

        var top: usize = 0;
        var bottom: usize = self.h;

        var x: usize = 0;
        var y: usize = 0;
        var w = self.w;
        var h = self.h;

        // find top pixel
        topPixelLoop: while (h > 0) : (h -= 1) {
            const row = self.pixels[y * w .. (y * w) + w];
            for (row) |p, i| {
                if (p & 0xFF000000 != 0) {
                    // row contains a pixel
                    break :topPixelLoop;
                }
            }
            y += 1;
            top += 1;
        }

        if (top != 0) {
            top -= padding;
            //reset h to new h
            h = self.h - y;
            // pad y
            y -= padding;
        }

        //find bottom pixel
        var tempY = self.h - 1;
        bottomPixelLoop: while (h > 0) : (h -= 1) {
            const row = self.pixels[tempY * w .. (tempY * w) + w];
            for (row) |p, i| {
                if (p & 0xFF000000 != 0) {
                    // row contains a pixel
                    break :bottomPixelLoop;
                }
            }
            tempY -= 1;
            bottom -= 1;
        }

        if (bottom != self.h) {
            h += padding;
        }

        // create a new image and copy over the vertically cropped pixels
        var verticalCroppedImage = Image.init(w, h);

        std.mem.copy(u32, verticalCroppedImage.pixels, self.pixels[top * w .. bottom * w]);

        //find left pixel
        w = verticalCroppedImage.w;
        h = verticalCroppedImage.h;
        tempY = 0;

        var leftPixel: usize = w;

        while (h > 0) : (h -= 1) {
            // iterate each row and find the one with the
            // left most pixel
            const row = verticalCroppedImage.pixels[tempY * w .. (tempY * w) + w];

            for (row) |p, i| {
                if (p & 0xFF000000 != 0) {
                    if (i < leftPixel)
                        leftPixel = i;

                    break;
                }
            }

            tempY += 1;
        }

        if (leftPixel != 0){
            // pad the left pixel
        leftPixel -= padding;

        }
        

        // x offset is now the leftmost pixel index
        x = leftPixel;

        // reset height for iteration
        h = verticalCroppedImage.h;

        var rightPixel: usize = 0;

        // find right pixel
        tempY = 0;
        while (h > 0) : (h -= 1) {
            const row = verticalCroppedImage.pixels[tempY * w .. (tempY * w) + w];

            var i = row.len - 1;

            while (i > 0) : (i -= 1) {
                if (row[i] & 0xFF000000 != 0) {
                    if (i > rightPixel)
                        rightPixel = i;
                    break;
                }
            }

            tempY += 1;
        }

        // pad right pixel
        if ( rightPixel != w){
            rightPixel += padding;

        }
        

        // create final image
        h = verticalCroppedImage.h;
        w = rightPixel - leftPixel;
        var croppedImage = Image.init(w, h);

        // copy rows into the final cropped image
        tempY = 0;
        while (h > 0) : (h -= 1) {
            const row = verticalCroppedImage.pixels[tempY * verticalCroppedImage.w .. (tempY * verticalCroppedImage.w) + verticalCroppedImage.w];
            const copy = row[leftPixel..rightPixel];
            const dest = croppedImage.pixels[tempY * croppedImage.w .. (tempY * croppedImage.w) + croppedImage.w];
            std.mem.copy(u32, dest, copy);

            tempY += 1;
        }

        self.w = croppedImage.w;
        self.h = croppedImage.h;

        // copy pixels into the existing image overwriting
        std.mem.copy(u32, self.pixels, croppedImage.pixels);

        return .{ .x = @intCast(i32, x), .y = @intCast(i32, y) };
    }
};
