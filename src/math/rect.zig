const std = @import("std");
const Edge = enum{
    left,
    right,
    top,
    bottom
};

pub const RectF = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,
};

pub const Rect = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,

    pub fn right(self: Rect) i32 {
        return self.x + self.width;
    }

    pub fn left(self: Rect) i32 {
        return self.x;
    }

    pub fn top(self: Rect) i32 {
        return self.y;
    }

    pub fn bottom(self: Rect) i32 {
        return self.y + self.height;
    }

    pub fn centerX(self: Rect) i32 {
        return self.x + @divTrunc(self.width, 2);
    }

    pub fn centerY(self: Rect) i32 {
        return self.y + @divTrunc(self.height, 2);
    }

    pub fn halfRect(self: Rect, edge: Edge) Rect {
        return switch (edge) {
            .top => Rect{ .x = self.x, .y = self.y, .width = self.width, .h = @divTrunc(self.height, 2) },
            .bottom => Rect{ .x = self.x, .y = self.y + @divTrunc(self.h, 2), .width = self.width, .height = @divTrunc(self.height, 2) },
            .left => Rect{ .x = self.x, .y = self.y, .width = @divTrunc(self.width, 2), .h = self.height },
            .right => Rect{ .x = self.x + @divTrunc(self.width, 2), .y = self.y, .width = @divTrunc(self.width, 2), .height = self.height },
        };
    }

    pub fn contract(self: *Rect, hor: i32, vert: i32) void {
        self.x += hor;
        self.y += vert;
        self.width -= hor * 2;
        self.height -= vert * 2;
    }

    pub fn expandEdge(self: *Rect, edge: Edge, move_x: i32) void {
        const amt = std.math.absInt(move_x) catch unreachable;

        switch (edge) {
            .top => {
                self.y -= amt;
                self.height += amt;
            },
            .bottom => {
                self.height += amt;
            },
            .left => {
                self.x -= amt;
                self.width += amt;
            },
            .right => {
                self.width += amt;
            },
        }
    }

    pub fn side(self: Rect, edge: Edge) i32 {
        return switch (edge) {
            .left => self.x,
            .right => self.x + self.width,
            .top => self.y,
            .bottom => self.y + self.height,
        };
    }

    pub fn contains(self: Rect, x: i32, y: i32) bool {
        return self.x <= x and x < self.right() and self.y <= y and y < self.bottom();
    }

    pub fn asRectF(self: Rect) RectF {
        return .{
            .x = @intToFloat(f32, self.x),
            .y = @intToFloat(f32, self.y),
            .width = @intToFloat(f32, self.width),
            .height = @intToFloat(f32, self.height),
        };
    }
};
