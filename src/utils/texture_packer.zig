const std = @import("std");
const fs = std.fs;
const Image = @import("../image.zig").Image;
const upaya = @import("../upaya.zig");
const math = upaya.math;
const stb = upaya.stb;

pub const TexturePacker = struct {

    pub const Size = struct {
        width: u16,
        height: u16,
    };

    pub const Sprite = struct {
        name: []const u8,
        source: math.Rect,
        origin: math.Point,
    };

    pub const Animation = struct {
        name: []const u8,
        indexes: []usize,
    };

    pub const Atlas = struct {
        sprites: []Sprite,
        width: u16,
        height: u16,
        image: upaya.Image = undefined,
        heightmap: upaya.Image = undefined,

        pub fn init(frames: []stb.stbrp_rect, origins: []math.Point, files: [][]const u8, images: []upaya.Image, heightmaps: []upaya.Image, size: Size) Atlas {
            std.debug.assert(frames.len == files.len and frames.len == origins.len and frames.len == images.len);

            var res_atlas = Atlas{
                .sprites = upaya.mem.allocator.alloc(Sprite, images.len) catch unreachable,
                .width = size.width,
                .height = size.height,
            };

            // convert to upaya rects
            for (frames) |frame, i| {
                res_atlas.sprites[i].source = .{ .x = frame.x, .y = frame.y, .width = frame.w, .height = frame.h };
                res_atlas.sprites[i].name = std.mem.dupe(upaya.mem.allocator, u8, files[i]) catch unreachable;
                res_atlas.sprites[i].origin = origins[i];
            }

            // generate the atlas
            var image = upaya.Image.init(size.width, size.height);
            image.fillRect(.{ .width = size.width, .height = size.height }, upaya.math.Color.transparent);

            for (images) |img, i| {
                image.blit(img, frames[i].x, frames[i].y);
            }

            var heightmap = upaya.Image.init(size.width, size.height);
            heightmap.fillRect(.{ .width = size.width, .height = size.height }, upaya.math.Color.transparent);

            for (heightmaps) |img, i| {
                heightmap.blit(img, frames[i].x, frames[i].y);
            }

            upaya.mem.allocator.free(images);
            upaya.mem.allocator.free(files);
            upaya.mem.allocator.free(frames);
            upaya.mem.allocator.free(origins);

            res_atlas.image = image;
            res_atlas.heightmap = heightmap;
            return res_atlas;
        }

        pub fn deinit(self: Atlas) void {
            for (self.sprites) |sprite| {
                upaya.mem.allocator.free(sprite.name);
            }
            upaya.mem.allocator.free(self.sprites);
            self.image.deinit();
        }

        /// saves the atlas image and a json file with the atlas details. filename should be only the name with no extension.
        pub fn save(self: Atlas, folder: []const u8, filename: []const u8) void {
            const img_filename = std.mem.concat(upaya.mem.allocator, u8, &[_][]const u8{ filename, ".png" }) catch unreachable;
            const atlas_filename = std.mem.concat(upaya.mem.allocator, u8, &[_][]const u8{ filename, ".atlas" }) catch unreachable;

            var out_file = fs.path.join(upaya.mem.tmp_allocator, &[_][]const u8{ folder, img_filename }) catch unreachable;
            self.image.save(out_file);

            // out_file = fs.path.join(upaya.mem.tmp_allocator, &[_][]const u8{ folder, heightmap_filename }) catch unreachable;
            // self.heightmap.save(out_file);

            out_file = fs.path.join(upaya.mem.tmp_allocator, &[_][]const u8{ folder, atlas_filename }) catch unreachable;
            var handle = std.fs.cwd().createFile(out_file, .{}) catch unreachable;
            defer handle.close();

            const out_stream = handle.writer();
            const options = std.json.StringifyOptions{ .whitespace = .{} };

            std.json.stringify(.{ .sprites = self.sprites }, options, out_stream) catch unreachable;
        }
    };

    pub fn runRectPacker(frames: []stb.stbrp_rect) ?Size {
        var ctx: stb.stbrp_context = undefined;
        const node_count = 4096 * 2;
        var nodes: [node_count]stb.stbrp_node = undefined;

        const texture_sizes = [_][2]c_int{
            [_]c_int{ 256, 256 },   [_]c_int{ 512, 256 },   [_]c_int{ 256, 512 },
            [_]c_int{ 512, 512 },   [_]c_int{ 1024, 512 },  [_]c_int{ 512, 1024 },
            [_]c_int{ 1024, 1024 }, [_]c_int{ 2048, 1024 }, [_]c_int{ 1024, 2048 },
            [_]c_int{ 2048, 2048 }, [_]c_int{ 4096, 2048 }, [_]c_int{ 2048, 4096 },
            [_]c_int{ 4096, 4096 }, [_]c_int{ 8192, 4096 }, [_]c_int{ 4096, 8192 },
        };

        for (texture_sizes) |tex_size| {
            stb.stbrp_init_target(&ctx, tex_size[0], tex_size[1], &nodes, node_count);
            stb.stbrp_setup_heuristic(&ctx, stb.STBRP_HEURISTIC_Skyline_BL_sortHeight);
            if (stb.stbrp_pack_rects(&ctx, frames.ptr, @intCast(c_int, frames.len)) == 1) {
                return Size{ .width = @intCast(u16, tex_size[0]), .height = @intCast(u16, tex_size[1]) };
            }
        }

        return null;
    }
};
