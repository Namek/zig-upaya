const std = @import("std");
const fs = std.fs;
const Image = @import("../../image.zig").Image;
const upaya = @import("../../upaya_cli.zig");
const math = upaya.math;
const stb = upaya.stb;

pub const PyxelEdit = struct {
    name: []const u8,
    canvas: CanvasJSON,
    version: []const u8,
    layers: []Layer,
    animations: []AnimationJSON,

    pub fn initFromFile(allocator: *std.mem.Allocator, file: []const u8) !PyxelEdit {
        @setEvalBranchQuota(2000);
        var zip_file = @ptrCast([*c]const u8, file);
        var zip = upaya.zip.zip_open(zip_file, 0, 'r');

        var buf: ?*c_void = null;
        var size: u64 = 0;

        _ = upaya.zip.zip_entry_open(zip, "docData.json");
        _ = upaya.zip.zip_entry_read(zip, &buf, &size);

        var content: []const u8 = @ptrCast([*]const u8, buf)[0..size];

        const layersText = "layers\": {";
        const layersEndText = "\"numLayers";
        const indexLayersStart = std.mem.indexOfPos(u8, content, 0, layersText).? + layersText.len;
        const indexLayersEnd = std.mem.indexOfPos(u8, content, indexLayersStart, layersEndText).? - 7;
        const layersContent = content[indexLayersStart..indexLayersEnd];

        const options = std.json.ParseOptions{ .allocator = allocator, .duplicate_field_behavior = .UseFirst, .ignore_unknown_fields = true, .allow_trailing_data = true };
        const pyxelEditJson = try std.json.parse(PyxelEditJSON, &std.json.TokenStream.init(content), options);
        defer std.json.parseFree(PyxelEditJSON, pyxelEditJson, options);

        var layers: std.ArrayList(Layer) = std.ArrayList(Layer).init(upaya.mem.allocator);

        var i: usize = 0;
        while (i < pyxelEditJson.canvas.numLayers) : (i += 1) {
            const startText = try std.fmt.allocPrint(upaya.mem.allocator, "\"{d}\": ", .{i});
            if (std.mem.indexOfPos(u8, layersContent, 0, startText)) |start| {
                var endText = try std.fmt.allocPrint(upaya.mem.allocator, "\"{d}\"", .{i + 1});

                if (std.mem.indexOfPos(u8, layersContent, start + startText.len, " },")) |end| {
                    const layerJSON = try std.json.parse(LayerJSON, &std.json.TokenStream.init(layersContent[start + startText.len .. end + 2]), options);
                    //defer std.json.parseFree(LayerJSON, layerJSON, options);
                    const layer: Layer = .{
                        .type = layerJSON.type,
                        .alpha = layerJSON.alpha,
                        .name = layerJSON.name,
                        .hidden = layerJSON.hidden,
                        .blendMode = layerJSON.blendMode,
                        .soloed = layerJSON.soloed,
                        .muted = layerJSON.muted,
                        .collapsed = layerJSON.collapsed,
                        .parentIndex = layerJSON.parentIndex,
                        .texture = undefined,
                    };

                    try layers.append(layer);
                    //std.debug.print("{s}", .{layersContent[start + startText.len - 1 .. end + 1]});
                } else {
                    var end = layersContent.len;
                    const layerJSON = try std.json.parse(LayerJSON, &std.json.TokenStream.init(layersContent[start + startText.len .. end]), options);
                    //defer std.json.parseFree(LayerJSON, layerJSON, options);
                    const layer: Layer = .{
                        .type = layerJSON.type,
                        .alpha = layerJSON.alpha,
                        .name = layerJSON.name,
                        .hidden = layerJSON.hidden,
                        .blendMode = layerJSON.blendMode,
                        .soloed = layerJSON.soloed,
                        .muted = layerJSON.muted,
                        .collapsed = layerJSON.collapsed,
                        .parentIndex = layerJSON.parentIndex,
                        .texture = undefined,
                    };
                    //defer std.json.parseFree(Layer, layer, options);
                    try layers.append(layer);
                }
            } else break;
        }

        const animationsText = "animations\": ";
        const indexAnimationStart = std.mem.indexOfPos(u8, content, 0, animationsText).? + animationsText.len;
        const indexAnimationEnd = size - 4;
        const animationsContent = content[indexAnimationStart..indexAnimationEnd];

        var animations: std.ArrayList(AnimationJSON) = std.ArrayList(AnimationJSON).init(upaya.mem.allocator);

        i = 0;
        while (true) : (i += 1) {
            const startText = try std.fmt.allocPrint(upaya.mem.allocator, "\"{d}\": ", .{i});
            if (std.mem.indexOfPos(u8, animationsContent, 0, startText)) |start| {
                var endText = try std.fmt.allocPrint(upaya.mem.allocator, "\"{d}\"", .{i + 1});

                if (std.mem.indexOfPos(u8, animationsContent, start + startText.len, " },")) |end| {
                    const animationsJSON = try std.json.parse(AnimationJSON, &std.json.TokenStream.init(animationsContent[start + startText.len .. end + 2]), options);
                    //defer std.json.parseFree(LayerJSON, layerJSON, options);

                    try animations.append(animationsJSON);

                    //std.debug.print("{s}", .{animationsContent[start + startText.len - 1 .. end + 1]});
                } else {
                    var end = animationsContent.len;
                    const animationsJSON = try std.json.parse(AnimationJSON, &std.json.TokenStream.init(animationsContent[start + startText.len .. end]), options);
                    //defer std.json.parseFree(LayerJSON, layerJSON, options);

                    //defer std.json.parseFree(Layer, layer, options);
                    try animations.append(animationsJSON);
                }
            } else {
                break;
            }
        }

        var pyxelEdit: PyxelEdit = .{
            .name = pyxelEditJson.name,
            .canvas = pyxelEditJson.canvas,
            .version = pyxelEditJson.version,
            .layers = layers.items,
            .animations = animations.items,
        };

        _ = upaya.zip.zip_entry_close(zip);

        i = 0;
        while (i < pyxelEdit.layers.len) : (i += 1) {
            var pngBuf: ?*c_void = null;
            var pngSize: u64 = 0;
            const png = try std.fmt.allocPrint(upaya.mem.allocator, "layer{d}.png\u{0}", .{i});

            _ = upaya.zip.zip_entry_open(zip, @ptrCast([*c]const u8, png));
            _ = upaya.zip.zip_entry_read(zip, &pngBuf, &pngSize);

            pyxelEdit.layers[i].texture = upaya.Image.initFromData(@ptrCast([*c]const u8, pngBuf), pngSize);

            _ = upaya.zip.zip_entry_close(zip);
            //upaya.zip.zip_close(zip);
        }

        upaya.zip.zip_close(zip);
        return pyxelEdit;
    }

    pub const PyxelEditJSON = struct {
        name: []const u8,
        canvas: CanvasJSON,
        version: []const u8,
    };

    pub const CanvasJSON = struct {
        height: i32,
        tileHeight: i32,
        numLayers: i32,
        currentLayerIndex: i32,
        width: i32,
        tileWidth: i32,
    };

    pub const Layer = struct {
        type: []const u8,
        alpha: u8,
        name: []const u8,
        hidden: bool,
        blendMode: []const u8,
        soloed: bool,
        muted: bool,
        collapsed: bool,
        parentIndex: i32,
        texture: upaya.Image,
    };

    pub const LayerJSON = struct {
        type: []const u8,
        alpha: u8,
        name: []const u8,
        hidden: bool,
        blendMode: []const u8,
        soloed: bool,
        muted: bool,
        collapsed: bool,
        parentIndex: i32,
    };

    // pub const Tileset = struct {
    //     tilesWide: i32,
    //     tileHeight: i32,
    //     numTiles: i32,
    //     tileWidth: i32,
    //     fixedWidth: bool,
    // };

    // pub const Palette = struct { height: i32, width: i32, numColors: i32, colors: struct {
    //     @"0": ?*u32,
    //     @"1": ?*u32,
    //     @"2": ?*u32,
    //     @"3": ?*u32,
    //     @"4": ?*u32,
    //     @"5": ?*u32,
    //     @"6": ?*u32,
    //     @"7": ?*u32,
    // } };

    pub const AnimationJSON = struct {
        frameDuration: i32,
        length: i32,
        frameDurationMultipliers: []i32,
        baseTile: i32,
        name: []const u8,
    };
};
