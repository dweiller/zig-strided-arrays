const std = @import("std");
const testing = std.testing;

const strided_array = @import("strided_array.zig");
const ViewError = strided_array.ViewError;

const TestArrayView = strided_array.StridedArrayView(u8, 3);
var one_to_23 = [24]TestArrayView.EltType{
    // zig fmt: off
     0,  1,  2,  3,  4,  5,  6,  7,
     8,  9, 10, 11, 12, 13, 14, 15,
    16, 17, 18, 19, 20, 21, 22, 23,
    // zig fmt: on
};

const ForAllSymmetries = @import("test_utils.zig").ForAllSymmetries;

test "StridedArrayView.sliceIndex()" {
    var array_view = TestArrayView{
        .items = one_to_23[0..],
        .stride = .{ 12, 4, 1 },
        .shape = .{ 2, 3, 4 },
        .offset = 0,
    };

    try testing.expectEqual(@as(usize, 0), array_view.sliceIndex(.{ 0, 0, 0 }));
    try testing.expectEqual(@as(usize, 15), array_view.sliceIndex(.{ 1, 0, 3 }));
    try testing.expectEqual(@as(usize, 23), array_view.sliceIndex(.{ 1, 2, 3 }));

    // overlapping window
    array_view.offset = 4;
    array_view.stride = .{ 4, 1, 1 };
    array_view.shape = .{ 5, 3, 2 };
    try testing.expectEqual(@as(usize, 4), array_view.sliceIndex(.{ 0, 0, 0 }));
    try testing.expectEqual(@as(usize, 5), array_view.sliceIndex(.{ 0, 0, 1 }));
    try testing.expectEqual(@as(usize, 5), array_view.sliceIndex(.{ 0, 1, 0 }));
    try testing.expectEqual(@as(usize, 7), array_view.sliceIndex(.{ 0, 2, 1 }));
    try testing.expectEqual(@as(usize, 8), array_view.sliceIndex(.{ 1, 0, 0 }));
    try testing.expectEqual(@as(usize, 15), array_view.sliceIndex(.{ 2, 2, 1 }));
    try testing.expectEqual(@as(usize, 16), array_view.sliceIndex(.{ 3, 0, 0 }));
    try testing.expectEqual(@as(usize, 18), array_view.sliceIndex(.{ 3, 1, 1 }));
    try testing.expectEqual(@as(usize, 18), array_view.sliceIndex(.{ 3, 2, 0 }));
    try testing.expectEqual(@as(usize, 23), array_view.sliceIndex(.{ 4, 2, 1 }));

    // overlapping but not unit
    array_view.offset = 0;
    array_view.stride = .{ 4, 2, 1 };
    array_view.shape = .{ 5, 3, 3 };
    try testing.expectEqual(@as(usize, 0), array_view.sliceIndex(.{ 0, 0, 0 }));
    try testing.expectEqual(@as(usize, 1), array_view.sliceIndex(.{ 0, 0, 1 }));
    try testing.expectEqual(@as(usize, 2), array_view.sliceIndex(.{ 0, 0, 2 }));
    try testing.expectEqual(@as(usize, 2), array_view.sliceIndex(.{ 0, 1, 0 }));
    try testing.expectEqual(@as(usize, 4), array_view.sliceIndex(.{ 0, 1, 2 }));
    try testing.expectEqual(@as(usize, 4), array_view.sliceIndex(.{ 1, 0, 0 }));
    try testing.expectEqual(@as(usize, 15), array_view.sliceIndex(.{ 3, 1, 1 }));
    try testing.expectEqual(@as(usize, 22), array_view.sliceIndex(.{ 4, 2, 2 }));
}

test "StridedArrayView.size()" {
    var array_view = TestArrayView{
        .items = one_to_23[0..],
        .stride = .{ 12, 4, 1 },
        .shape = .{ 2, 3, 4 },
        .offset = 0,
    };

    try testing.expectEqual(@as(usize, 0), TestArrayView.sizeOf(.{ 0, 2, 4 }));

    const size_func = struct {
        fn f(ctx: usize, av: TestArrayView) !void {
            try testing.expectEqual(ctx, av.size());
        }
    }.f;

    const size_test = ForAllSymmetries(usize, TestArrayView, size_func);

    {
        const s = size_test{ .ctx = 24 };
        try s.run(&array_view);
    }

    // strided
    array_view.stride = .{ 12, 4, 2 };
    array_view.shape = .{ 2, 3, 2 };
    {
        const s = size_test{ .ctx = 12 };
        try s.run(&array_view);
    }

    // overlapping window
    array_view.offset = 4;
    array_view.stride = .{ 4, 1, 1 };
    array_view.shape = .{ 5, 3, 2 };
    {
        const s = size_test{ .ctx = 30 };
        try s.run(&array_view);
    }

    // overlapping but not unit
    array_view.offset = 0;
    array_view.stride = .{ 4, 2, 1 };
    array_view.shape = .{ 5, 3, 3 };
    {
        const s = size_test{ .ctx = 45 };
        try s.run(&array_view);
    }
}

test "StridedArrayView.iterator()" {
    var array_view = TestArrayView{
        .items = one_to_23[0..],
        .stride = .{ 12, 4, 1 },
        .shape = .{ 2, 3, 4 },
        .offset = 0,
    };
    {
        var iter = array_view.iterate();
        var i: usize = 0;
        while (iter.next()) |val| : (i += 1) {
            try testing.expectEqual(i, val);
        }
        try testing.expectEqual(@as(usize, 24), i);
    }
    // strided
    array_view.stride = .{ 12, 4, 2 };
    array_view.shape = .{ 2, 3, 2 };
    {
        const exp = [_]TestArrayView.EltType{
            // zig fmt: off
             0, 2,
             4, 6,
             8, 10,

            12, 14,
            16, 18,
            20, 22,
            // zig fmt: on
        };
        var iter = array_view.iterate();
        var i: usize = 0;
        while (iter.next()) |val| : (i += 1) {
            try testing.expectEqual(exp[i], val);
        }
        try testing.expectEqual(@as(usize, 12), i);
    }

    // strided + offset
    array_view.stride = .{ 12, 4, 2 };
    array_view.shape = .{ 2, 3, 2 };
    array_view.offset = 1;
    {
        const exp = [_]TestArrayView.EltType{
            // zig fmt: off
             1,  3,
             5,  7,
             9, 11,

            13, 15,
            17, 19,
            21, 23,
            // zig fmt: on
        };
        var iter = array_view.iterate();
        var i: usize = 0;
        while (iter.next()) |val| : (i += 1) {
            try testing.expectEqual(exp[i], val);
        }
        try testing.expectEqual(@as(usize, 12), i);
    }

    // leave off last elt of inner dimension
    array_view.stride = .{ 12, 4, 1 };
    array_view.shape = .{ 2, 3, 3 };
    array_view.offset = 0;
    {
        const exp = [_]TestArrayView.EltType{
            // zig fmt: off
             0,  1,  2,
             4,  5,  6,
             8,  9, 10,

            12, 13, 14,
            16, 17, 18,
            20, 21, 22,
            // zig fmt: on
        };
        var iter = array_view.iterate();
        var i: usize = 0;
        while (iter.next()) |val| : (i += 1) {
            try testing.expectEqual(exp[i], val);
        }
        try testing.expectEqual(@as(usize, 18), i);
    }

    // overlapping
    array_view.offset = 4;
    array_view.stride = .{ 4, 1, 1 };
    array_view.shape = .{ 5, 3, 2 };
    {
        const exp = [_]TestArrayView.EltType{
            // zig fmt: off
             4,  5,  5,  6,  6,  7,
             8,  9,  9, 10, 10, 11,
            12, 13, 13, 14, 14, 15,
            16, 17, 17, 18, 18, 19,
            20, 21, 21, 22, 22, 23,
            // zig fmt: on
        };
        var iter = array_view.iterate();
        var i: usize = 0;
        while (iter.next()) |val| : (i += 1) {
            try testing.expectEqual(exp[i], val);
        }
        try testing.expectEqual(@as(usize, 30), i);
    }

    // overlapping but not unit
    array_view.offset = 0;
    array_view.stride = .{ 4, 2, 1 };
    array_view.shape = .{ 5, 3, 3 };
    {
        const exp = [_]TestArrayView.EltType{
            // zig fmt: off
             0,  1,  2,  2,  3,  4,  4,  5,  6,
             4,  5,  6,  6,  7,  8,  8,  9, 10,
             8,  9, 10, 10, 11, 12, 12, 13, 14,
            12, 13, 14, 14, 15, 16, 16, 17, 18,
            16, 17, 18, 18, 19, 20, 20, 21, 22,
            // zig fmt: on
        };
        var iter = array_view.iterate();
        var i: usize = 0;
        while (iter.next()) |val| : (i += 1) {
            try testing.expectEqual(exp[i], val);
        }
        try testing.expectEqual(@as(usize, 45), i);
    }
}

test "StridedArrayVIew.iterateWrap()" {
    var array_view = TestArrayView{
        .items = one_to_23[0..],
        .stride = .{ 12, 4, 1 },
        .shape = .{ 2, 3, 4 },
        .offset = 0,
    };
    {
        const exp = [_]TestArrayView.EltType{
            // zig fmt: off
             0,  1,  2,  3,  0,  1,  2,  3,
             4,  5,  6,  7,  4,  5,  6,  7,
             8,  9, 10, 11,  8,  9, 10, 11,
             0,  1,  2,  3,  0,  1,  2,  3,
             4,  5,  6,  7,  4,  5,  6,  7,

            12, 13, 14, 15, 12, 13, 14, 15,
            16, 17, 18, 19, 16, 17, 18, 19,
            20, 21, 22, 23, 20, 21, 22, 23,
            12, 13, 14, 15, 12, 13, 14, 15,
            16, 17, 18, 19, 16, 17, 18, 19,
            // zig fmt: on
        };
        var iter = array_view.iterateWrap(.{0, 0, 0}, .{2, 5, 8});
        var i: usize = 0;
        while (iter.next()) |item| : (i += 1) {
            try testing.expectEqual(exp[i], item);
        }
    }
}

test "StridedArrayView.transpose()" {
    var array_view = TestArrayView{
        .items = one_to_23[0..],
        .stride = .{ 12, 4, 1 },
        .shape = .{ 2, 3, 4 },
        .offset = 0,
    };
    array_view.transpose(1, 2);
    {
        const exp = [_]TestArrayView.EltType{
            // zig fmt: off
             0,  4,  8,  1,
             5,  9,  2,  6,
            10,  3,  7, 11,

            12, 16, 20, 13,
            17, 21, 14, 18,
            22, 15, 19, 23,
            // zig fmt: on
        };
        var iter = array_view.iterate();
        var i: usize = 0;
        while (iter.next()) |val| : (i += 1) {
            try testing.expectEqual(exp[i], val);
        }
    }
    array_view.transpose(1, 2);
    array_view.transpose(0, 2);
    {
        const exp = [_]TestArrayView.EltType{
            // zig fmt: off
             0, 12,  4, 16,
             8, 20,  1, 13,
             5, 17,  9, 21,

             2, 14,  6, 18,
            10, 22,  3, 15,
             7, 19, 11, 23,
            // zig fmt: on
        };
        var iter = array_view.iterate();
        var i: usize = 0;
        while (iter.next()) |val| : (i += 1) {
            try testing.expectEqual(exp[i], val);
        }
    }

    // overlapping but not unit
    array_view.offset = 0;
    array_view.stride = .{ 4, 2, 1 };
    array_view.shape = .{ 5, 3, 3 };
    array_view.transpose(1, 2);
    {
        const exp = [_]TestArrayView.EltType{
            // zig fmt: off
             0,  2,  4,  1,  3,  5,  2,  4,  6,
             4,  6,  8,  5,  7,  9,  6,  8, 10,
             8, 10, 12,  9, 11, 13, 10, 12, 14,
            12, 14, 16, 13, 15, 17, 14, 16, 18,
            16, 18, 20, 17, 19, 21, 18, 20, 22,
            // zig fmt: on
        };
        var iter = array_view.iterate();
        var i: usize = 0;
        while (iter.next()) |val| : (i += 1) {
            try testing.expectEqual(exp[i], val);
        }
    }

}

test "StridedArrayView.flip()" {
    var array_view = TestArrayView{
        .items = one_to_23[0..],
        .stride = .{ 12, 4, 1 },
        .shape = .{ 2, 3, 4 },
        .offset = 0,
    };
    array_view.flip(2);
    {
        const exp = [_]TestArrayView.EltType{
            // zig fmt: off
             3,  2,  1,  0,
             7,  6,  5,  4,
            11, 10,  9,  8,

            15, 14, 13, 12,
            19, 18, 17, 16,
            23, 22, 21, 20,
            // zig fmt: on
        };
        var iter = array_view.iterate();
        var i: usize = 0;
        while (iter.next()) |val| : (i += 1) {
            try testing.expectEqual(exp[i], val);
        }
    }
    array_view.flip(2);
    array_view.flip(1);
    {
        const exp = [_]TestArrayView.EltType{
            // zig fmt: off
             8,  9, 10, 11,
             4,  5,  6,  7,
             0,  1,  2,  3,

            20, 21, 22, 23,
            16, 17, 18, 19,
            12, 13, 14, 15,
            // zig fmt: on
        };
        var iter = array_view.iterate();
        var i: usize = 0;
        while (iter.next()) |val| : (i += 1) {
            try testing.expectEqual(exp[i], val);
        }
    }
}

test "StridedArrayView.slice()" {
    var array_view = TestArrayView{
        .items = one_to_23[0..],
        .stride = .{ 12, 4, 1 },
        .shape = .{ 2, 3, 4 },
        .offset = 0,
    };

    // trying to slice outside the bounds
    try testing.expect(array_view.sliceOrNull(.{2, 2, 2}, .{1, 1, 1}) == null);
    try testing.expect(array_view.sliceOrNull(.{1, 2, 2}, .{1, 2, 1}) == null);
    try testing.expect(array_view.sliceOrNull(.{1, 2, 2}, .{1, 1, 3}) == null);

    // a '2D' slice
    {
        const view_opt = array_view.sliceOrNull(.{0, 1, 1}, .{1, 2, 3});
        try testing.expect(view_opt != null);
        const view = view_opt.?;
        const exp = [_]TestArrayView.EltType{
            // zig fmt: off
            5,  6,  7,
            9, 10, 11,
            // zig fmt: on
        };
        var iter = view.iterate();
        var i: usize = 0;
        while (iter.next()) |val| : (i += 1) {
            try testing.expectEqual(exp[i], val);
        }
    }

    // a slice with zero size is not valid
    {
        const view_opt = array_view.sliceOrNull(.{0, 1, 1}, .{0, 2, 3});
        try testing.expect(view_opt == null);
    }
}

test "StridedArrayView.sliceStep()" {
    var array_view = TestArrayView{
        .items = one_to_23[0..],
        .stride = .{ 12, 4, 1 },
        .shape = .{ 2, 3, 4 },
        .offset = 0,
    };

    // trying to slice outside the bounds
    try testing.expect(array_view.sliceStepOrNull(.{2, 2, 2}, .{1, 1, 1}, .{1, 1, 1}) == null);
    try testing.expect(array_view.sliceStepOrNull(.{1, 2, 2}, .{1, 2, 1}, .{1, 1, 1}) == null);
    try testing.expect(array_view.sliceStepOrNull(.{1, 2, 2}, .{1, 1, 3}, .{1, 1, 1}) == null);

    // a '2D' slice
    {
        const view_opt = array_view.sliceStepOrNull(.{0, 0, 1}, .{2, 3, 3}, .{1, 2, 2});
        try testing.expect(view_opt != null);
        const view = view_opt.?;
        const exp = [_]TestArrayView.EltType{
            // zig fmt: off
             1,  3,
             9, 11,

            13, 15,
            21, 23,
            // zig fmt: on
        };
        var iter = view.iterate();
        var i: usize = 0;
        while (iter.next()) |val| : (i += 1) {
            try testing.expectEqual(exp[i], val);
        }
        try testing.expectEqual(exp.len, i);
    }

    // a slice with zero size is not valid
    {
        const view_opt = array_view.sliceStepOrNull(.{0, 1, 1}, .{0, 2, 3}, .{1, 1, 1});
        try testing.expect(view_opt == null);
    }
}

test "StridedArrayView.slidingWindow()" {
    var array_view = TestArrayView{
        .items = one_to_23[0..],
        .stride = .{ 12, 4, 1 },
        .shape = .{ 2, 3, 4 },
        .offset = 0,
    };

    const window = array_view.slidingWindow(2, .{3, 3});
    try testing.expectEqualSlices(u32, &.{2, 1, 2, 3, 3}, window.shape[0..]);
    try testing.expectEqualSlices(TestArrayView.StrideType, &.{12, 4, 1, 4, 1}, window.stride[0..]);
    {
        const exp = [_]TestArrayView.EltType{
            // zig fmt: off
            0, 1,  2,
            4, 5,  6,
            8, 9, 10,

            1, 2,  3,
            5, 6,  7,
            9, 10, 11,

            12, 13, 14,
            16, 17, 18,
            20, 21, 22,

            13, 14, 15,
            17, 18, 19,
            21, 22, 23,
            // zig fmt: on
        };
        var iter = window.iterate();
        var i: usize = 0;
        while (iter.next()) |val| : (i += 1) {
            try testing.expectEqual(exp[i], val);
        }
    }
}
