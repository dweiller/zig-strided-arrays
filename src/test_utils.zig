const std = @import("std");

pub fn ForAllSymmetries(
    comptime T: type,
    comptime TestArrayView: type,
    comptime func: fn (T, TestArrayView) anyerror!void,
) type {
    return struct {
        const Self = @This();

        ctx: T,

        pub fn run(self: Self, array_view: *TestArrayView) !void {
            // transpositions
            {
                for (0..TestArrayView.dim_count) |i| {
                    for (0..TestArrayView.dim_count) |j| {
                        array_view.transpose(i, j);
                        try func(self.ctx, array_view.*);
                        array_view.transpose(i, j);
                    }
                }
            }

            // transposition + flip (i.e. rotation) note that when i == j, it's just a flip
            {
                for (0..TestArrayView.dim_count) |i| {
                    for (0..TestArrayView.dim_count) |j| {
                        array_view.transpose(i, j);
                        for (0..TestArrayView.dim_count) |k| {
                            array_view.flip(k);
                            try func(self.ctx, array_view.*);
                            array_view.flip(k);
                        }
                        array_view.transpose(i, j);
                    }
                }
            }
        }
    };
}
