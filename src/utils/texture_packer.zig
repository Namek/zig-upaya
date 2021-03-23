const std = @import("std");
const fs = std.fs;
const Image = @import("../image.zig").Image;
const upaya = @import("../upaya_cli.zig");
const math = upaya.math;
const stb = upaya.stb;

pub const TexturePacker = struct {
    pub const Sprite = struct {
        name: []const u8,
        source: math.Rect,
        origin: math.Point,
    };

    pub const Atlas = struct {
        sprites: []Sprite,
        width: u16,
        height: u16,
        image: upaya.Image = undefined,
        heightmap: upaya.Image = undefined,

        pub fn init(frames: []stb.stbrp_rect, origins: []math.Point, files: [][]const u8, size: Size, method: PackingMethod) Atlas {
            std.debug.assert(frames.len == files.len);
            var res_atlas = Atlas{
                .sprites = upaya.mem.allocator.alloc(Sprite, files.len) catch unreachable,
                .width = size.width,
                .height = size.height,
            };

            // convert to upaya rects
            for (frames) |frame, i| {
                res_atlas.sprites[i].source = .{ .x = frame.x, .y = frame.y, .width = frame.w, .height = frame.h };
            }

            for (files) |file, i| {
                res_atlas.sprites[i].name = upaya.mem.allocator.dupe(u8, fs.path.basename(file)) catch unreachable;
            }

            for (origins) |origin, i| {
                res_atlas.sprites[i].origin = origin;
            }

            // generate the atlas
            var image = upaya.Image.init(size.width, size.height);
            image.fillRect(.{ .width = size.width, .height = size.height }, upaya.math.Color.transparent);

            var heightmap = upaya.Image.init(size.width, size.height);
            heightmap.fillRect(.{ .width = size.width, .height = size.height }, upaya.math.Color.transparent);

            for (files) |file, i| {
                var sub_image = upaya.Image.initFromFile(file);
                defer sub_image.deinit();
                if (method == .Tight) {
                    _ = sub_image.crop();
                }
                image.blit(sub_image, frames[i].x, frames[i].y);

                var height_sub_image = upaya.Image.initFromFile(file);
                defer height_sub_image.deinit();

                var r: u8 = 1;
                var row: i32 = @intCast(i32, height_sub_image.h);
                var containsColor: bool = false;
                var j: usize = height_sub_image.pixels.len - 1;
                while (j > 0) : (j -= 1) {
                    var temp_row = @intCast(i32, @divTrunc(j, height_sub_image.w));

                    if (temp_row != row and r < 255) {
                        
                            r += 1;
                            row = temp_row;
                    
                    }

                    if (height_sub_image.pixels[j] & 0xFF000000 != 0) {
                        var color = upaya.math.Color.fromBytes(r, r, r, 255);
                        height_sub_image.pixels[j] = color.value;
                        containsColor = true;
                    }
                }

                if (method == .Tight) {
                    _ = height_sub_image.crop();
                }

                heightmap.blit(height_sub_image, frames[i].x, frames[i].y);
            }

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
            const heightmap_filename = std.mem.concat(upaya.mem.allocator, u8, &[_][]const u8{ filename, "_h.png" }) catch unreachable;

            var out_file = fs.path.join(upaya.mem.tmp_allocator, &[_][]const u8{ folder, img_filename }) catch unreachable;
            self.image.save(out_file);

            out_file = fs.path.join(upaya.mem.tmp_allocator, &[_][]const u8{ folder, heightmap_filename }) catch unreachable;
            self.heightmap.save(out_file);

            out_file = fs.path.join(upaya.mem.tmp_allocator, &[_][]const u8{ folder, atlas_filename }) catch unreachable;
            var handle = std.fs.cwd().createFile(out_file, .{}) catch unreachable;
            defer handle.close();

            const out_stream = handle.writer();
            const options = std.json.StringifyOptions{ .whitespace = .{} };

            std.json.stringify(.{ .sprites = self.sprites }, options, out_stream) catch unreachable;
        }
    };

    pub const Size = struct {
        width: u16,
        height: u16,
    };

    pub const PackingMethod = enum {
        Full,
        Tight,
    };

    pub fn pack(folder: []const u8, method: PackingMethod) !Atlas {
        const pngs = upaya.fs.getAllFilesOfType(upaya.mem.allocator, folder, ".png", true);

        var origins = std.ArrayList(math.Point).init(upaya.mem.allocator);

        const frames = getFramesForPngs(pngs, &origins, method);

        if (runRectPacker(frames)) |atlas_size| {
            return Atlas.init(frames, origins.items, pngs, atlas_size, method);
        } else {
            return error.NotEnoughRoom;
        }
    }

    fn getFramesForPngs(pngs: [][]const u8, origins: *std.ArrayList(math.Point), method: PackingMethod) []stb.stbrp_rect {
        var frames = std.ArrayList(stb.stbrp_rect).init(upaya.mem.allocator);
        for (pngs) |png, i| {
            var w: c_int = undefined;
            var h: c_int = undefined;

            var tex = upaya.Image.initFromFile(png);
            defer tex.deinit();

            if (method == .Tight) {
                var offset = tex.crop();
                origins.*.append(.{ .x = 0 - offset.x, .y = 0 - offset.y }) catch unreachable;
            }

            if (method == .Full) {
                origins.*.append(.{ .x = 0, .y = 0 }) catch unreachable;
            }

            frames.append(.{
                .id = @intCast(c_int, i),
                .w = @intCast(u16, tex.w),
                .h = @intCast(u16, tex.h),
            }) catch unreachable;
        }

        return frames.toOwnedSlice();
    }

    fn runRectPacker(frames: []stb.stbrp_rect) ?Size {
        var ctx: stb.stbrp_context = undefined;
        const rects_size = @sizeOf(stb.stbrp_rect) * frames.len;
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
            stb.stbrp_setup_heuristic(&ctx, stb.STBRP_HEURISTIC_Skyline_default);
            if (stb.stbrp_pack_rects(&ctx, frames.ptr, @intCast(c_int, frames.len)) == 1) {
                return Size{ .width = @intCast(u16, tex_size[0]), .height = @intCast(u16, tex_size[1]) };
            }
        }

        return null;
    }
};
