const std = @import("std");

pub fn ForAllSymmetries(comptime T: type, comptime TestArrayView: type, func: fn (T, TestArrayView) anyerror!void) type {
    return struct {
        const Self = @This();

        ctx: T,

        pub fn run(self: Self, array_view: *TestArrayView) !void {
            // transpositions
            {
                var i: usize = 0;
                while (i < TestArrayView.dim_count) : (i += 1) {
                    var j: usize = 0;
                    while (j < TestArrayView.dim_count) : (j += 1) {
                        array_view.transpose(i, j);
                        try func(self.ctx, array_view.*);
                        array_view.transpose(i, j);
                    }
                }
            }

            // transposition + flip (i.e. rotation) note that when i == j, it's just a flip
            {
                var i: usize = 0;
                while (i < TestArrayView.dim_count) : (i += 1) {
                    var j: usize = 0;
                    while (j < TestArrayView.dim_count) : (j += 1) {
                        array_view.transpose(i, j);
                        var k: usize = 0;
                        while (k < TestArrayView.dim_count) : (k += 1) {
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

