const std = @import("std");
const upaya = @import("upaya");
const math = upaya.math;
const colors = upaya.colors;
const fs = std.fs;
usingnamespace upaya.imgui;
const stb = upaya.stb;

var atlas: ?upaya.TexturePacker.Atlas = null;
var texture: ?upaya.Texture = null;

var folder: []const u8 = undefined;

var tight: bool = false;
var defaultOrigin: c_int = 0;
var origin_x: c_int = 0;
var origin_y: c_int = 0;

pub fn main() !void {
    upaya.run(.{
        .init = init,
        .update = update,
        .shutdown = shutdown,
        .docking = false,
        .width = 1024,
        .height = 768,
        .window_title = "Texture Packer",
        .onFileDropped = onFileDropped,
    });
}

fn init() void {}

fn shutdown() void {
    if (atlas) |a| a.deinit();
}

fn update() void {
    ogSetNextWindowPos(.{}, ImGuiCond_Always, .{});
    ogSetNextWindowSize(.{
        .x = @intToFloat(f32, upaya.sokol.sapp_width()),
        .y = @intToFloat(f32, upaya.sokol.sapp_height()),
    }, ImGuiCond_Always);

    if (igBegin("Main Window", null, ImGuiWindowFlags_NoTitleBar)) {
        if (atlas) |a| {
            igText("Atlas Size:");
            igSameLine(0, 5);

            igSetNextItemWidth(100);
            var tmp_size = [_]c_int{ @intCast(c_int, a.width), @intCast(c_int, a.height) };
            _ = igInputInt2("", &tmp_size, ImGuiInputTextFlags_None);
            igSameLine(0, 5);

            if (ogButton("Save to Desktop")) {
                const path_or_null = upaya.known_folders.getPath(upaya.mem.tmp_allocator, .desktop) catch unreachable;
                if (path_or_null) |path| atlas.?.save(path, "test");
            }
            igSameLine(0, 10);

            igText("Method:");
            igSameLine(0, 5);
            if (igCheckbox("Tight", &tight)) onFileDropped(folder);

            igSameLine(0, 10);
            igText("Origin:");
            igSameLine(0, 5);
            if (igRadioButtonIntPtr("TL", &defaultOrigin, 0)) onFileDropped(folder);
            igSameLine(0, 5);
            if (igRadioButtonIntPtr("TR", &defaultOrigin, 1)) onFileDropped(folder);
            igSameLine(0, 5);
            if (igRadioButtonIntPtr("BL", &defaultOrigin, 2)) onFileDropped(folder);
            igSameLine(0, 5);
            if (igRadioButtonIntPtr("BR", &defaultOrigin, 3)) onFileDropped(folder);
            igSameLine(0, 5);
            if (igRadioButtonIntPtr("C", &defaultOrigin, 4)) onFileDropped(folder);
            igSameLine(0, 5);
            if (igRadioButtonIntPtr("Custom", &defaultOrigin, 5)) onFileDropped(folder);

            if (defaultOrigin == 5) {
                igSetNextItemWidth(100);
                igSameLine(0, 5);
                if (igSliderInt("x", &origin_x, 0, 100, "%.0f")) onFileDropped(folder);
                igSetNextItemWidth(100);
                igSameLine(0, 5);
                if (igSliderInt("y", &origin_y, 0, 100, "%.0f")) onFileDropped(folder);
            }

            defer igEndChild();
            if (ogBeginChildEx("#child", 666, ogGetContentRegionAvail(), true, ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_HorizontalScrollbar)) {
                var pos = ogGetCursorScreenPos();
                const size = ImVec2{ .x = @intToFloat(f32, a.width), .y = @intToFloat(f32, a.height) };

                ogAddRectFilled(igGetWindowDrawList(), pos, size, colors.rgbToU32(39, 40, 48));
                ogAddRect(igGetWindowDrawList(), pos, size, colors.rgbToU32(155, 0, 155), 1);
                _ = ogInvisibleButton("##rects", size, ImGuiButtonFlags_None);

                for (a.sprites) |sprite, i| {
                    const tl = .{ .x = pos.x + @intToFloat(f32, sprite.source.x), .y = pos.y + @intToFloat(f32, sprite.source.y) };
                    ogAddRect(igGetWindowDrawList(), tl, .{ .x = @intToFloat(f32, sprite.source.width), .y = @intToFloat(f32, sprite.source.height) }, colors.rgbToU32(0, 255, 0), 1);

                    drawChunk(tl, sprite.source.asRectF());

                    const o = .{ .x = tl.x + @intToFloat(f32, sprite.origin.x), .y = tl.y + @intToFloat(f32, sprite.origin.y) };
                    ogAddRect(igGetWindowDrawList(), o, .{ .x = 1, .y = 1 }, colors.rgbToU32(255, 0, 0), 2);
                }
            }
        } else {
            var pos = ogGetCursorScreenPos();
            const size = ogGetContentRegionAvail();
            ogAddRectFilled(igGetWindowDrawList(), pos, size, colors.rgbToU32(39, 40, 48));
            ogAddRect(igGetWindowDrawList(), pos, size, colors.rgbToU32(39, 40, 48), 10);

            var text_size: ImVec2 = undefined;
            igCalcTextSize(&text_size, "Drag/drop a folder", null, false, 1024);
            ogSetCursorPos(.{ .x = (size.x / 2) - text_size.x, .y = size.y / 2 });

            igGetCurrentContext().FontSize *= 2;
            igText("Drag/drop a folder");
            igGetCurrentContext().FontSize /= 2;
        }
    }
    igEnd();
}

fn drawChunk(tl: ImVec2, rect: math.RectF) void {
    var br = tl;
    br.x += rect.width;
    br.y += rect.height;

    const inv_w = 1.0 / @intToFloat(f32, atlas.?.width);
    const inv_h = 1.0 / @intToFloat(f32, atlas.?.height);

    const uv0 = ImVec2{ .x = rect.x * inv_w, .y = rect.y * inv_h };
    const uv1 = ImVec2{ .x = (rect.x + rect.width) * inv_w, .y = (rect.y + rect.height) * inv_h };

    ogImDrawList_AddImage(igGetWindowDrawList(), texture.?.imTextureID(), tl, br, uv0, uv1, 0xFFFFFFFF);

}

fn onFileDropped(file: []const u8) void {
    if (fs.cwd().openDir(file, .{ .iterate = true })) |dir| {
        folder = file;
        var config: upaya.TexturePacker.AtlasConfig = .{
            .method = if (tight) .Tight else .Full,
            .default_origin = @intToEnum(upaya.TexturePacker.DefaultOrigin, @intCast(u3, defaultOrigin)),
            .custom_origin = .{ .x = origin_x, .y = origin_y },
        };
        atlas = upaya.TexturePacker.pack(file, config) catch unreachable;
        if (texture) |tex| tex.deinit();
        texture = atlas.?.image.asTexture(.nearest);
    } else |err| {
        std.debug.print("Dropped a non-directory: {}, err: {}\n", .{ file, err });
    }
}
