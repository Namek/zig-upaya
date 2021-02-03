const std = @import("std");
const upaya = @import("upaya");
const math = upaya.math;
const colors = upaya.colors;
const fs = std.fs;
usingnamespace upaya.imgui;
const stb = upaya.stb;

var looseAtlas: ?upaya.TexturePacker.Atlas = null;
var tightAtlas: ?upaya.TexturePacker.Atlas = null;

var looseTexture: ?upaya.Texture = null;
var tightTexture: ?upaya.Texture = null;

var atlas: ?upaya.TexturePacker.Atlas = null;

var folder: []const u8 = undefined;

var tight: bool = false;
var preserveOrigins: bool = true;

var defaultOrigin: c_int = 0;
var origin_x: c_int = 0;
var origin_y: c_int = 0;

var offsets: std.ArrayList(upaya.math.Point) = undefined;

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
    offsets = std.ArrayList(upaya.math.Point).init(upaya.mem.allocator);

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
    //origins.deinit();
}

fn update() void {
    atlas = if (tight) tightAtlas else looseAtlas;

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

            if (igIsKeyPressed(igGetKeyIndex(ImGuiKey_Escape), false) and selection.items.len > 0) {
                selection.shrinkAndFree(0);
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

            igSameLine(0, 20);
            igText("Method:");

            // offer option to pack tightly or loosely (full rects)
            igSameLine(0, 5);
            if (igCheckbox(if (tight) "Tight" else "Loose", &tight)) {
                if (tight) {
                    atlas = tightAtlas;

                    if (preserveOrigins) {
                        for (atlas.?.sprites) |sprite, i| {
                            atlas.?.sprites[i].origin.x = looseAtlas.?.sprites[i].origin.x + offsets.items[i].x;
                            atlas.?.sprites[i].origin.y = looseAtlas.?.sprites[i].origin.y + offsets.items[i].y;
                        }
                    } else {
                        for (atlas.?.sprites) |sprite, i| {
                            atlas.?.sprites[i].origin.x = looseAtlas.?.sprites[i].origin.x;
                            atlas.?.sprites[i].origin.y = looseAtlas.?.sprites[i].origin.y;
                        }

                    }

                } else {
                    atlas = looseAtlas;
                }
            }

            // offer option to preserve origins from original rects
            if (tight) {
                igSameLine(0, 5);
                if (igCheckbox("Preserve Origins", &preserveOrigins)) {
                    if (preserveOrigins) {
                        for (atlas.?.sprites) |sprite, i| {
                            atlas.?.sprites[i].origin.x += offsets.items[i].x;
                            atlas.?.sprites[i].origin.y += offsets.items[i].y;
                        }
                    } else {
                        for (atlas.?.sprites) |sprite, i| {
                            atlas.?.sprites[i].origin.x -= offsets.items[i].x;
                            atlas.?.sprites[i].origin.y -= offsets.items[i].y;
                        }
                    }
                }
            }

            // offer options for zooming in and out
            igSameLine(0, 20);
            igText("Zoom:");
            igSameLine(0, 5);
            igSetNextItemWidth(100);
            _ = igInputFloat("", if (snapZoom) &snappedZoom else &zoom, if (snapZoom) 1.0 else 0.02, 1.0, "%.1f", ImGuiInputTextFlags_None);
            zoom = if (zoom <= 0) 0.2 else zoom;
            snappedZoom = if (snappedZoom < 1) 1 else snappedZoom;
            igSameLine(0, 5);
            _ = igCheckbox(if (snapZoom) "Snap" else "Smooth", &snapZoom);

            // begin drawing the actual sprites to the sheet
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

                // draw sprites and check if any are hovered to handle selection
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

                // loop through and draw any selection rects in a second pass so they draw over all sprites
                for (selection.items) |select, i| {
                    const tl = .{ .x = pos.x + @intToFloat(f32, a.sprites[select].source.x) * if (snapZoom) snappedZoom else zoom, .y = pos.y + @intToFloat(f32, a.sprites[select].source.y) * if (snapZoom) snappedZoom else zoom };
                    const sprSize = .{ .x = @intToFloat(f32, a.sprites[select].source.width) * if (snapZoom) snappedZoom else zoom, .y = @intToFloat(f32, a.sprites[select].source.height) * if (snapZoom) snappedZoom else zoom };

                    ogAddRect(igGetWindowDrawList(), tl, sprSize, colors.rgbToU32(0, 255, 0), 1);
                }

                // loop through and draw any origins in another pass so they draw over all rects
                for (selection.items) |select, i| {
                    const tl = .{ .x = pos.x + @intToFloat(f32, a.sprites[select].source.x) * if (snapZoom) snappedZoom else zoom, .y = pos.y + @intToFloat(f32, a.sprites[select].source.y) * if (snapZoom) snappedZoom else zoom };
                    // draw origin
                    const o = .{ .x = tl.x + @intToFloat(f32, a.sprites[select].origin.x) * if (snapZoom) snappedZoom else zoom, .y = tl.y + @intToFloat(f32, a.sprites[select].origin.y) * if (snapZoom) snappedZoom else zoom };
                    ogAddRect(igGetWindowDrawList(), o, .{ .x = 1, .y = 1 }, colors.rgbToU32(255, 0, 0), 2);
                }
            }
        } else {
            // draw a empty page to drag and drop a folder for packing
            var pos = ogGetCursorScreenPos();
            const size = ogGetContentRegionAvail();
            ogAddRectFilled(igGetWindowDrawList(), pos, size, bgColor);

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

    if (igBegin("Selection", null, ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize)) {
        defer igEnd();

        if (atlas) |a| {
            var pos = ogGetWindowPos();
            var size = ogGetWindowSize();
            //background
            ogAddRectFilled(igGetWindowDrawList(), pos, size, popBgColor);

            var selectedOrigin: c_int = 0;
            var currentSprite: upaya.TexturePacker.Sprite = undefined;

            if (selection.items.len == 1) {
                igText(@ptrCast([*c]const u8, a.sprites[selection.items[0]].name));

                currentSprite = a.sprites[selection.items[0]];
            } else if (selection.items.len > 1) {
                var count = std.fmt.allocPrint(upaya.mem.allocator, "({})", .{selection.items.len}) catch unreachable;
                igText(@ptrCast([*c]const u8, count));

                currentSprite = a.sprites[selection.items[selection.items.len - 1]];
            }

            const o_tl: upaya.math.Point = .{ .x = 0, .y = 0 };
            const o_tr: upaya.math.Point = .{ .x = currentSprite.source.width, .y = 0 };
            const o_bl: upaya.math.Point = .{ .x = 0, .y = currentSprite.source.height };
            const o_br: upaya.math.Point = .{ .x = currentSprite.source.width, .y = currentSprite.source.height };
            const o_c: upaya.math.Point = .{ .x = @divTrunc(currentSprite.source.width, 2), .y = @divTrunc(currentSprite.source.height, 2) };

            if (currentSprite.origin.x == o_tl.x and currentSprite.origin.y == o_tl.y) {
                selectedOrigin = 0;
                origin_x = o_tl.x;
                origin_y = o_tl.y;
            } else if (currentSprite.origin.x == o_tr.x and currentSprite.origin.y == o_tr.y) {
                selectedOrigin = 1;
                origin_x = o_tr.x;
                origin_y = o_tr.y;
            } else if (currentSprite.origin.x == o_bl.x and currentSprite.origin.y == o_bl.y) {
                selectedOrigin = 2;
                origin_x = o_bl.x;
                origin_y = o_bl.y;
            } else if (currentSprite.origin.x == o_br.x and currentSprite.origin.y == o_br.y) {
                selectedOrigin = 3;
                origin_x = o_br.x;
                origin_y = o_br.y;
            } else if (currentSprite.origin.x == o_c.x and currentSprite.origin.y == o_c.y) {
                selectedOrigin = 4;
                origin_x = o_c.x;
                origin_y = o_c.y;
            } else {
                selectedOrigin = 5;
                origin_x = currentSprite.origin.x;
                origin_y = currentSprite.origin.y;
            }

            igText("Origin:");
            if (igRadioButtonIntPtr("TopLeft", &selectedOrigin, 0)) {
                if (tight and preserveOrigins) {
                    for (selection.items) |index| {
                        a.sprites[index].origin = .{ .x = offsets.items[index].x, .y = offsets.items[index].y };
                    }
                } else {
                    for (selection.items) |index| {
                        a.sprites[index].origin = .{ .x = 0, .y = 0 };
                    }
                }
            }
            if (igRadioButtonIntPtr("TopRight", &selectedOrigin, 1)) {
                if (tight and preserveOrigins) {
                    for (selection.items) |index| {
                        a.sprites[index].origin = .{ .x = a.sprites[index].source.width + offsets.items[index].x, .y = offsets.items[index].y };
                    }
                } else {
                    for (selection.items) |index| {
                        a.sprites[index].origin = .{ .x = a.sprites[index].source.width, .y = 0 };
                    }
                }
            }
            if (igRadioButtonIntPtr("BottomLeft", &selectedOrigin, 2)) {
                if (tight and preserveOrigins) {
                    for (selection.items) |index| {
                        a.sprites[index].origin = .{ .x = offsets.items[index].x, .y = a.sprites[index].source.height + offsets.items[index].y };
                    }
                } else {
                    for (selection.items) |index| {
                        a.sprites[index].origin = .{ .x = 0, .y = a.sprites[index].source.height };
                    }
                }
            }
            if (igRadioButtonIntPtr("BottomRight", &selectedOrigin, 3)) {
                if (tight and preserveOrigins) {
                    for (selection.items) |index| {
                        a.sprites[index].origin = .{ .x = a.sprites[index].source.width + offsets.items[index].x, .y = a.sprites[index].source.height + offsets.items[index].y };
                    }
                } else {
                    for (selection.items) |index| {
                        a.sprites[index].origin = .{ .x = a.sprites[index].source.width, .y = a.sprites[index].source.height };
                    }
                }
            }
            if (igRadioButtonIntPtr("Center", &selectedOrigin, 4)) {
                if (tight and preserveOrigins) {
                    for (selection.items) |index| {
                        a.sprites[index].origin = .{ .x = @divTrunc(a.sprites[index].source.width, 2) + offsets.items[index].x, .y = (@divTrunc(a.sprites[index].source.height, 2) + offsets.items[index].y) };
                    }
                } else {
                    for (selection.items) |index| {
                        a.sprites[index].origin = .{ .x = @divTrunc(a.sprites[index].source.width, 2), .y = @divTrunc(a.sprites[index].source.height, 2) };
                    }
                }
            }
            _ = igRadioButtonIntPtr("Custom", &selectedOrigin, 5);

            igSetNextItemWidth(100);
            if (igInputInt("x", &origin_x, 1, 10, ImGuiTextFlags_None)) {
                if (tight and preserveOrigins) {
                    for (selection.items) |index| {
                        a.sprites[index].origin = .{ .x = origin_x + offsets.items[index].x, .y = a.sprites[index].origin.y };
                    }
                } else {
                    for (selection.items) |index| {
                        a.sprites[index].origin = .{ .x = origin_x, .y = a.sprites[index].origin.y };
                    }
                }
            }
            igSetNextItemWidth(100);
            if (igInputInt("y", &origin_y, 1, 10, ImGuiTextFlags_None)) {
                if (tight and preserveOrigins) {
                    for (selection.items) |index| {
                        a.sprites[index].origin = .{ .x = a.sprites[index].origin.x, .y = (origin_y + offsets.items[index].y) };
                    }
                } else {
                    for (selection.items) |index| {
                        a.sprites[index].origin = .{ .x = a.sprites[index].origin.x, .y = origin_y };
                    }
                }
            }
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

    var texture = if (tight) tightTexture else looseTexture;

    ogImDrawList_AddImage(igGetWindowDrawList(), texture.?.imTextureID(), tl, br, uv0, uv1, 0xFFFFFFFF);
}

fn onFileDropped(file: []const u8) void {
    if (fs.cwd().openDir(file, .{ .iterate = true })) |dir| {
        folder = file;
    
        tightAtlas = upaya.TexturePacker.pack(file, .{ .method = .Tight, .default_origin = .TL }) catch unreachable;
        looseAtlas = upaya.TexturePacker.pack(file, .{ .method = .Full, .default_origin = .TL }) catch unreachable;

        if (tightTexture) |tex| tex.deinit();
        if (looseTexture) |tex| tex.deinit();

        tightTexture = tightAtlas.?.image.asTexture(.nearest);
        looseTexture = looseAtlas.?.image.asTexture(.nearest);

        offsets.deinit();
        offsets = std.ArrayList(upaya.math.Point).initCapacity(upaya.mem.allocator, tightAtlas.?.sprites.len) catch unreachable;
        offsets.expandToCapacity();

        for (tightAtlas.?.sprites) |sprite, i| {
            // when this is run, the tight sprite origin is equal to its offset
            offsets.items[i] = sprite.origin;
        }
    } else |err| {
        std.debug.print("Dropped a non-directory: {}, err: {}\n", .{ file, err });
    }
}
