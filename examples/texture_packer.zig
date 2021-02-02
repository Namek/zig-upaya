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

var origins: std.ArrayList(upaya.math.Point) = undefined;
var selection: std.ArrayList(usize) = undefined;

var selectAll: bool = true;
var selected: usize = 0;

var zoom: f32 = 1.0;
var snappedZoom: f32 = 1.0;
var snapZoom: bool = true;
var zoomSpeed: f32 = 0.05;

const bgColor = 0xFF362C2A;
const popBgColor = 0x77362C2A;

const checkerColor1 = 0xFF888888;
const checkerColor2 = 0xFFAAAAAA;
var checkerTexture: ?upaya.Texture = null;

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

fn init() void {
    origins = std.ArrayList(upaya.math.Point).init(upaya.mem.allocator);
    selection = std.ArrayList(usize).init(upaya.mem.allocator);

    var checkerPixels = [_]u32{
        checkerColor1, checkerColor2, checkerColor1, checkerColor2,
        checkerColor2, checkerColor1, checkerColor2, checkerColor1,
        checkerColor1, checkerColor2, checkerColor1, checkerColor2,
        checkerColor2, checkerColor1, checkerColor2, checkerColor1,
    };
    checkerTexture = upaya.Texture.initWithColorData(&checkerPixels, 4, 4, .nearest, .repeat);
}

fn shutdown() void {
    if (atlas) |a| a.deinit();
    selection.deinit();
    origins.deinit();
}

fn update() void {
    drawSelectionPopup();

    var io = igGetIO();
    // set zoom
    if (io.MouseWheel > 0 and io.KeyCtrl) {
        zoom += zoomSpeed;
        snappedZoom = @intToFloat(f32, @floatToInt(i32, zoom));
    } else if (io.MouseWheel < 0 and io.KeyCtrl) {
        if (zoom - zoomSpeed > 0)
            zoom -= zoomSpeed;

        snappedZoom = @intToFloat(f32, @floatToInt(i32, zoom));
    }

    ogSetNextWindowPos(.{}, ImGuiCond_Always, .{});
    ogSetNextWindowSize(.{
        .x = @intToFloat(f32, upaya.sokol.sapp_width()),
        .y = @intToFloat(f32, upaya.sokol.sapp_height()),
    }, ImGuiCond_Always);

    if (igBegin("Main Window", null, ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoBringToFrontOnFocus | ImGuiWindowFlags_NoResize)) {
        ogAddRectFilled(igGetWindowDrawList(), .{}, ogGetWindowSize(), bgColor);

        if (atlas) |a| {

            // allow select all
            if (io.KeySuper or io.KeyCtrl) {
                if (igIsKeyPressed(igGetKeyIndex(ImGuiKey_A), false)) {
                    selection.shrinkAndFree(0);

                    for (a.sprites) |sprite, i| {
                        selection.append(i) catch unreachable;
                    }
                }
            }

            igText("Atlas Size:");
            igSameLine(0, 5);

            igSetNextItemWidth(100);
            var tmp_size = [_]c_int{ @intCast(c_int, a.width), @intCast(c_int, a.height) };
            _ = igInputInt2("", &tmp_size, ImGuiInputTextFlags_None);
            igSameLine(0, 5);

            if (ogButton("Save to Desktop")) {
                const path_or_null = upaya.known_folders.getPath(upaya.mem.tmp_allocator, .desktop) catch unreachable;
                if (path_or_null) |path| atlas.?.save(path, "output");
            }
            igSameLine(0, 10);

            igText("Method:");
            igSameLine(0, 5);
            if (igCheckbox(if (tight) "Tight" else "Loose", &tight)) onFileDropped(folder);

            igSameLine(0, 10);
            igText("Zoom:");
            igSameLine(0, 5);
            igSetNextItemWidth(100);
            _ = igInputFloat("", if (snapZoom) &snappedZoom else &zoom, if (snapZoom) 1.0 else 0.02, 1.0, "%.1f",ImGuiInputTextFlags_None);
            zoom = if (zoom <= 0) 0.2 else zoom;
            snappedZoom = if (snappedZoom < 1) 1 else snappedZoom;
            igSameLine(0, 5);
            _ = igCheckbox(if (snapZoom) "Snap" else "Smooth", &snapZoom);

            defer igEndChild();
            if (ogBeginChildEx("#child", 666, ogGetContentRegionAvail(), true, ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_HorizontalScrollbar | ImGuiWindowFlags_NoBackground)) {
                var pos = ogGetCursorScreenPos();
                const size = ImVec2{ .x = @intToFloat(f32, a.width) * if (snapZoom) snappedZoom else zoom, .y = @intToFloat(f32, a.height) * if (snapZoom) snappedZoom else zoom };

                var availableSize = ogGetWindowSize();
                var centered_x = ((availableSize.x - size.x) / 2);
                var centered_y = ((availableSize.y - size.y) / 2);

                if (size.x < availableSize.x)
                    pos.x += centered_x;

                if (size.y < availableSize.y)
                    pos.y += centered_y;

                ogImDrawList_AddImage(igGetWindowDrawList(), checkerTexture.?.imTextureID(), pos, .{ .x = pos.x + size.x, .y = pos.y + size.y }, .{}, .{ .x = 20, .y = 20 }, 0xFFFFFFFF);
                _ = ogInvisibleButton("##rects", size, ImGuiButtonFlags_None);

                // first loop draw sprites
                for (a.sprites) |sprite, i| {
                    const tl = .{ .x = pos.x + @intToFloat(f32, sprite.source.x) * if (snapZoom) snappedZoom else zoom, .y = pos.y + @intToFloat(f32, sprite.source.y) * if (snapZoom) snappedZoom else zoom };
                    const sprSize = .{ .x = @intToFloat(f32, sprite.source.width) * if (snapZoom) snappedZoom else zoom, .y = @intToFloat(f32, sprite.source.height) * if (snapZoom) snappedZoom else zoom };

                    drawChunk(tl, sprite.source.asRectF());

                    ogSetCursorScreenPos(tl);
                    _ = ogInvisibleButton("##sprite", sprSize, ImGuiButtonFlags_None);

                    if (igIsItemHovered(ImGuiHoveredFlags_RectOnly)) {
                        ogAddRect(igGetWindowDrawList(), tl, sprSize, colors.rgbaToU32(255, 255, 0, 128), 1);

                        if (igIsMouseReleased(ImGuiMouseButton_Left)) {
                            if (io.KeyCtrl) {
                                var contains = false;
                                for (selection.items) |s, ii| {
                                    if (i == s) {
                                        contains = true;
                                        _ = selection.swapRemove(ii);
                                    }
                                }

                                if (!contains)
                                    selection.append(i) catch unreachable;
                            } else {
                                selection.shrinkAndFree(0);
                                //selection.items[0] = i;
                                selection.append(i) catch unreachable;
                            }
                        }
                    }
                }

                for (selection.items) |select, i| {
                    const tl = .{ .x = pos.x + @intToFloat(f32, a.sprites[select].source.x) * if (snapZoom) snappedZoom else zoom, .y = pos.y + @intToFloat(f32, a.sprites[select].source.y) * if (snapZoom) snappedZoom else zoom };
                    const sprSize = .{ .x = @intToFloat(f32, a.sprites[select].source.width) * if (snapZoom) snappedZoom else zoom, .y = @intToFloat(f32, a.sprites[select].source.height) * if (snapZoom) snappedZoom else zoom };

                    ogAddRect(igGetWindowDrawList(), tl, sprSize, colors.rgbToU32(0, 255, 0), 1);
                }

                for (selection.items) |select, i| {
                    const tl = .{ .x = pos.x + @intToFloat(f32, a.sprites[select].source.x) * if (snapZoom) snappedZoom else zoom, .y = pos.y + @intToFloat(f32, a.sprites[select].source.y) * if (snapZoom) snappedZoom else zoom };
                    // draw origin
                    const o = .{ .x = tl.x + @intToFloat(f32, origins.items[select].x) * if (snapZoom) snappedZoom else zoom, .y = tl.y + @intToFloat(f32, origins.items[select].y) * if (snapZoom) snappedZoom else zoom };
                    ogAddRect(igGetWindowDrawList(), o, .{ .x = 1, .y = 1 }, colors.rgbToU32(255, 0, 0), 2);
                }
            }
        } else {
            var pos = ogGetCursorScreenPos();
            const size = ogGetContentRegionAvail();
            ogAddRectFilled(igGetWindowDrawList(), pos, size, bgColor);
            //ogAddRect(igGetWindowDrawList(), pos, size, colors.rgbToU32(39, 40, 48), 10);

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

fn drawSelectionPopup() void {
    if (selection.items.len == 0)
        return;

    if (igBegin("Selection", null, ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoBackground)) {
        defer igEnd();

        var pos = ogGetWindowPos();
        var size = ogGetWindowSize();

        ogAddRectFilled(igGetWindowDrawList(), pos, size, popBgColor);

        if (selection.items.len == 1) {
            if (atlas) |a| {
                igText(@ptrCast([*c]const u8, a.sprites[selection.items[0]].name));
            }
        } else if (selection.items.len > 1) {
            var count = std.fmt.allocPrint(upaya.mem.allocator, "({})", .{selection.items.len}) catch unreachable;
            igText(@ptrCast([*c]const u8, count));
        }

        igText("Origin:");
        if (igRadioButtonIntPtr("TopLeft", &defaultOrigin, 0)) onFileDropped(folder);
        if (igRadioButtonIntPtr("TopRight", &defaultOrigin, 1)) onFileDropped(folder);
        if (igRadioButtonIntPtr("BottomLeft", &defaultOrigin, 2)) onFileDropped(folder);
        if (igRadioButtonIntPtr("BottomRight", &defaultOrigin, 3)) onFileDropped(folder);
        if (igRadioButtonIntPtr("Center", &defaultOrigin, 4)) onFileDropped(folder);
        if (igRadioButtonIntPtr("Custom", &defaultOrigin, 5)) onFileDropped(folder);

        if (defaultOrigin == 5) {
            igSetNextItemWidth(100);
            if (igInputInt("x", &origin_x, 1, 10, ImGuiTextFlags_None)) onFileDropped(folder);
            igSetNextItemWidth(100);
            if (igInputInt("y", &origin_y, 1, 10, ImGuiTextFlags_None)) onFileDropped(folder);
        }
    }
}

fn drawChunk(tl: ImVec2, rect: math.RectF) void {
    var br = tl;
    br.x += rect.width * if (snapZoom) snappedZoom else zoom;
    br.y += rect.height * if (snapZoom) snappedZoom else zoom;

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

        origins.deinit();
        origins = std.ArrayList(upaya.math.Point).initCapacity(upaya.mem.allocator, atlas.?.sprites.len) catch unreachable;
        origins.expandToCapacity();

        for (atlas.?.sprites) |sprite, i| {
            origins.items[i] = sprite.origin;
        }
    } else |err| {
        std.debug.print("Dropped a non-directory: {}, err: {}\n", .{ file, err });
    }
}
