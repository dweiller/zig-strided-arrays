//! This module provides a generic StridedArrayView type.
//!
//! A strided array view is an `n`-dimensional view into a slice of type `[]T`. A particular view allows access to a subset of the slice via `n`-dimensional coordinates, or by iterating over elements of the subset in row-major order.
//!
//! Strided array views also allow cheap _logical_ reordering of the underlying slice, allowing dimensions to be arbritrarily transposed, flipped and rotated and resized (as long as the new shape makes sense).

const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const GridError = error{
    IndexOutOfBounds,
    BufferTooSmall,
    ZeroLengthDimension,
};

pub const ViewError = error{
    InvalidView,
    OverlappingElementsUnsupported,
};

pub fn StridedArrayView(comptime T: type, comptime num_dims: usize) type {
    const bit_size = @typeInfo(usize).Int.bits / 2;
    return StridedArrayViewIdx(T, num_dims, @Type(.{ .Int = .{ .bits = bit_size, .signedness = .unsigned } }));
}

pub fn StridedArrayViewIdx(comptime T: type, comptime num_dims: usize, comptime IndexType: type) type {
    return struct {
        const Self = @This();

        const info = @typeInfo(IndexType);
        comptime {
            if (info != .Int or info.Int.signedness == .signed) {
                @compileError("StridedArrayView IndexType must be an unsigned integer type");
            }
            if (info.Int.bits > 64) {
                @compileError(std.fmt.comptimePrint("Maximum allowed bit size is for IndexType is 64; got {d}-bit type", .{info.Int.bits}));
            }
        }

        pub const Indices = [num_dims]IndexType;
        pub const StrideType = @Type(.{ .Int = .{ .bits = 2 * info.Int.bits, .signedness = .signed } });
        pub const Stride = [num_dims]StrideType;

        pub const dim_count = num_dims;
        pub const EltType = T;

        items: []T,
        stride: Stride,
        shape: Indices,
        offset: IndexType,

        fn strideOfShapePacked(shape: Indices) Stride {
            var stride: Stride = undefined;
            for (stride) |_, i| {
                stride[i] = shape[i];
            }
            stride[stride.len - 1] = 1;
            var i = shape.len - 1;
            while (i > 0) : (i -= 1) {
                stride[i - 1] = stride[i] * shape[i];
            }
            return stride;
        }

        fn validView(self: Self) bool {
            return if (self.size() > 0 and self.maxCoordIndex() < self.items.len)
                true
            else
                false;
        }

        fn maxCoordIndex(self: Self) usize {
            var max_coord = self.shape;
            for (max_coord) |*v| {
                v.* -= 1;
            }
            return self.sliceIndex(max_coord);
        }

        /// Create a packed view (i.e. a view with no gaps between elements in the underlying slice)
        pub fn ofSlicePacked(items: []T, shape: Indices) !Self {
            return ofSliceStrided(items, strideOfShapePacked(shape), shape);
        }

        /// Create a view with the given `stride`s.
        pub fn ofSliceStrided(items: []T, stride: Stride, shape: Indices) !Self {
            return ofSliceExtra(items, 0, stride, shape);
        }

        /// Create a view with the given `stride`s and `offset` into the underylying slice.
        pub fn ofSliceExtra(items: []T, offset: IndexType, stride: Stride, shape: Indices) !Self {
            const view = Self{
                .items = items,
                .stride = stride,
                .shape = shape,
                .offset = offset,
            };
            if (!view.validView())
                return ViewError.InvalidView;
            return view;
        }

        fn isValid(self: Self, coord: Indices) bool {
            comptime var i = 0;
            inline while (i < num_dims) : (i += 1) {
                if (coord[i] >= self.shape[i]) {
                    return false;
                }
            }
            return true;
        }

        /// Returns the index in the underlying slice of the element at `coord`,
        /// or `null` if `coord` is not valid.
        pub fn sliceIndexOrNull(self: Self, coord: Indices) ?usize {
            return if (self.isValid(coord)) self.sliceIndex(coord) else null;
        }

        /// Returns the index in the underlying slice of the element at `coord`.
        /// The caller guarantees that `coord` is valid.
        pub fn sliceIndex(self: Self, coord: Indices) usize {
            var index: StrideType = @as(StrideType, self.offset);
            comptime var i = 0;
            inline while (i < num_dims) : (i += 1) {
                index += coord[i] * self.stride[i];
            }
            return @intCast(usize, index);
        }

        /// Returns the iteration index for row-major ordering of the element at `coord`,
        /// or `null` if `coord` if not valid.
        pub fn iterIndexOrNull(self: Self, coord: Indices) ?usize {
            return if (self.isValid(coord)) self.iterIndex(coord) else null;
        }

        /// Returns the iteration index for row-major ordering or the element at `coord`.
        pub fn iterIndex(self: Self, coord: Indices) usize {
            var index: usize = coord[num_dims - 1];

            comptime var dim = num_dims - 1;
            var s: usize = 1;
            inline while (dim > 0) : (dim -= 1) {
                s *= self.shape[dim];
                index += coord[dim - 1] * s;
            }
            return index;
        }

        /// Returns coordinates in row-major order
        pub fn coordOfIterIndex(self: Self, index: usize) Indices {
            var coord: Indices = undefined;
            var idx = index;
            comptime var i = num_dims;
            inline while (i > 0) : (i -= 1) {
                coord[i - 1] = @intCast(IndexType, idx % @as(usize, self.shape[i - 1]));
                idx /= self.shape[i - 1];
            }
            return coord;
        }

        fn strideGreaterThan(stride: Stride, a: usize, b: usize) bool {
            const l = std.math.absCast(stride[a]);
            const r = std.math.absCast(stride[b]);
            return l > r;
        }

        fn strideOrdering(self: Self) [num_dims]usize {
            var dims = comptime dims: {
                var res: [num_dims]usize = undefined;
                var i = 0;
                while (i < num_dims) : (i += 1) {
                    res[i] = i;
                }
                break :dims res;
            };
            std.sort.sort(usize, dims[0..], self.stride, strideGreaterThan);
            return dims;
        }

        fn viewOverlapping(self: Self, order: [num_dims]usize) bool {
            var overlapping = false;
            comptime var i = 0;
            inline while (i < num_dims - 1) : (i += 1) {
                overlapping = overlapping or
                    std.math.absCast(self.stride[order[i]]) < std.math.absCast(self.stride[order[i + 1]] * self.shape[order[i + 1]]);
            }
            return overlapping;
        }

        /// Returns ViewError.OverlappingElementsUnsupported if the view has overlapping elements
        fn coordOfSliceIndex(self: Self, index: IndexType) !Indices {
            const dims_in_order = self.strideOrdering();
            if (self.viewOverlapping(dims_in_order)) {
                return ViewError.OverlappingElementsUnsupported;
            }
            var coord: Indices = undefined;
            var idx = @as(StrideType, index - self.offset);

            comptime var i = 0;
            inline while (i < self.stride.len) : (i += 1) {
                coord[dims_in_order[i]] = @intCast(IndexType, @divTrunc(idx, self.stride[dims_in_order[i]]));
                idx = @rem(idx, self.stride[dims_in_order[i]]);
            }
            return coord;
        }

        /// Returns the element at `coord`, or `null` if `coord` is invalid.
        pub fn getOrNull(self: Self, coord: Indices) ?T {
            return if (self.isValid(coord)) self.get(coord) else null;
        }

        /// Returns the element at `coord`; asserts that `coord` is valid.
        pub fn get(self: Self, coord: Indices) T {
            return self.items[self.sliceIndex(coord)];
        }

        /// Returns a pointer to the element at `coord`, or `null` if `coord` is invalid.
        pub fn getPtrOrNull(self: Self, coord: Indices) ?*T {
            return if (self.isValid(coord)) self.getPtr(coord) else null;
        }

        /// Returns a pointer to the element at `coord`; asserts that `coord` is valid.
        pub fn getPtr(self: Self, coord: Indices) *T {
            return &self.items[self.sliceIndex(coord)];
        }

        /// Sets the value at `coord`; asserts that `coord` is valid.
        pub fn set(self: Self, coord: Indices, value: T) void {
            self.items[self.sliceIndex(coord)] = value;
        }

        /// Returns the size of a view with the provided `shape`.
        pub fn sizeOf(shape: Indices) usize {
            var result: usize = 1;
            comptime var i = 0;
            inline while (i < num_dims) : (i += 1) {
                result *= shape[i];
            }
            return result;
        }

        /// Returns the size of a view.
        pub fn size(self: Self) usize {
            return sizeOf(self.shape);
        }

        pub const Iterator = struct {
            index: usize,
            last: usize,
            array_view: Self,

            pub fn nextSliceIndex(self: *Iterator) ?usize {
                if (self.index >= self.last) return null;
                const coord = self.array_view.coordOfIterIndex(self.index);
                const index = self.array_view.sliceIndex(coord);
                self.index += 1;
                return index;
            }

            pub fn next(self: *Iterator) ?T {
                const index = self.nextSliceIndex() orelse return null;
                return self.array_view.items[index];
            }

            pub fn nextPtr(self: *Iterator) ?*T {
                const index = self.nextSliceIndex() orelse return null;
                return &self.array_view.items[index];
            }

            pub const PtrInd = struct {
                ptr: *T,
                index: usize,
            };

            pub fn nextPtrWithIndex(self: *Iterator) ?PtrInd {
                const index = self.index;
                const ptr = self.nextPtr() orelse return null;
                return PtrInd{
                    .ptr = ptr,
                    .index = index,
                };
            }

            pub const PtrCoord = struct {
                ptr: *T,
                coord: Indices,
            };

            pub fn nextPtrWithCoord(self: *Iterator) ?PtrCoord {
                const coord = self.array_view.coordOfIterIndex(self.index);
                const ptr = self.nextPtr() orelse return null;
                return PtrCoord{
                    .ptr = ptr,
                    .coord = coord,
                };
            }

            pub const PtrCoordInd = struct {
                ptr: *T,
                coord: Indices,
                index: usize,
            };

            pub fn nextPtrWithBoth(self: *Iterator) ?PtrCoordInd {
                const index = self.index;
                const coord = self.array_view.coordOfIterIndex(index);
                const ptr = self.nextPtr() orelse return null;
                return PtrCoordInd{
                    .ptr = ptr,
                    .coord = coord,
                    .index = index,
                };
            }

            pub const TInd = struct {
                val: T,
                index: usize,
            };

            pub fn nextWithIndex(self: *Iterator) ?TInd {
                const index = self.index;
                const item = self.next() orelse return null;
                return TInd{
                    .val = item,
                    .index = index,
                };
            }

            pub const TCoord = struct {
                val: T,
                coord: Indices,
            };

            pub fn nextWithCoord(self: *Iterator) ?TCoord {
                const coord = self.array_view.coordOfIterIndex(self.index);
                const item = self.next() orelse return null;
                return TCoord{
                    .val = item,
                    .coord = coord,
                };
            }

            pub const TCoordInd = struct {
                val: T,
                coord: Indices,
                index: usize,
            };

            pub fn nextWithBoth(self: *Iterator) ?TCoordInd {
                const index = self.index;
                const coord = self.array_view.coordOfIterIndex(index);
                const item = self.next() orelse return null;
                return TCoordInd{
                    .val = item,
                    .coord = coord,
                    .index = index,
                };
            }
        };

        /// Iterate over the whole view.
        pub fn iterate(self: Self) Iterator {
            return self.iterateFrom(0);
        }

        /// Iterate from (iteration) index `first` to the end of the view.
        pub fn iterateFrom(self: Self, first: usize) Iterator {
            return self.iterateRange(first, self.size());
        }

        /// Iterate over the view up to (iteration) index `last`.
        pub fn iterateTo(self: Self, last: usize) Iterator {
            return self.iterateRange(0, last);
        }

        /// Iterate from (iteration) index `first` to `last`.
        pub fn iterateRange(self: Self, first: usize, last: usize) Iterator {
            return Iterator{
                .index = first,
                .last = last,
                .array_view = self,
            };
        }

        pub const WrapIterator = struct {
            offset: Indices,
            coord: Indices,
            shape: Indices,
            done: bool,
            array_view: Self,

            pub fn next(self: *WrapIterator) ?T {
                const coord = self.coord;
                if (self.done) return null;

                var underlying_coord: Indices = undefined;
                for (underlying_coord) |_, i| {
                    underlying_coord[i] = (self.offset[i] + coord[i]) % self.array_view.shape[i];
                }

                var iter_coord = self.coord;
                var dim = self.shape.len - 1;
                iter_coord[dim] = (iter_coord[dim] + 1) % self.shape[dim];
                while (dim > 0 and iter_coord[dim] == 0) : (dim -= 1) {
                    iter_coord[dim - 1] = (iter_coord[dim - 1] + 1) % self.shape[dim - 1];
                }

                if (dim == 0 and iter_coord[0] == 0) self.done = true;

                self.coord = iter_coord;

                return self.array_view.get(underlying_coord);
            }
        };

        /// Iterate over the given region, but wrap coordinates along each dimension.
        /// If wrapping behaviour is not needed or desired, you can `slice()` to the
        /// shape desired and then `iterate()` instead.
        pub fn iterateWrap(self: Self, from: Indices, shape: Indices) WrapIterator {
            const start = [1]IndexType{0} ** num_dims;
            return WrapIterator{
                .offset = from,
                .coord = start,
                .shape = shape,
                .done = false,
                .array_view = self,
            };
        }

        /// Copy data to `buf`. See `copyToAlloc()` for a wrapper that takes an allocator.
        pub fn copyTo(self: Self, buf: []T) void {
            std.debug.assert(buf.len >= self.size());
            var iter = self.iterate();
            var i: usize = 0;
            while (iter.next()) |val| : (i += 1) {
                buf[i] = val;
            }
        }

        /// Copy data to a newly allocated slice.
        pub fn copyToAlloc(self: Self, allocator: Allocator) ![]T {
            const buf = try allocator.alloc(T, self.size());
            self.copyTo(buf);
            return buf;
        }

        /// Transpose dimensions `dim_1` and `dim_2`.
        pub fn transpose(self: *Self, dim_1: usize, dim_2: usize) void {
            std.mem.swap(StrideType, &self.stride[dim_1], &self.stride[dim_2]);
            std.mem.swap(IndexType, &self.shape[dim_1], &self.shape[dim_2]);
        }

        /// Flip dimension `dim` to run in the opposite direction.
        pub fn flip(self: *Self, dim: usize) void {
            self.offset = @intCast(IndexType, @as(StrideType, self.offset) + self.stride[dim] * (self.shape[dim] - 1));
            self.stride[dim] = -self.stride[dim];
        }

        /// Returns a new view containing the sub-region starting at `from`
        /// with the given shape, or null if `shape` is not valid.
        pub fn sliceOrNull(self: Self, from: Indices, shape: Indices) ?Self {
            const view = self.slice(from, shape);
            return if (view.validView()) view else null;
        }

        /// Returns a new view containing the sub-region starting at `from`
        /// with the given shape. Do not slice to a shape that has zero size
        /// (i.e. any dimension is zero).
        pub fn slice(self: Self, from: Indices, shape: Indices) Self {
            return Self{
                .items = self.items,
                .shape = shape,
                .stride = self.stride,
                .offset = @intCast(IndexType, self.sliceIndex(from)),
            };
        }

        /// Returns a new view containing the sub-region starting at `from`
        /// with the given shape and step size or null if invalid shape/step
        /// combination is passed. Note that `shape` corresponds to the region
        /// in the original view (i.e. if all steps are 1) and each component of
        /// `steps` must be non-zero. Prefer `sliceOrNull` if stepping is not
        /// required.
        pub fn sliceStepOrNull(self: Self, from: Indices, shape: Indices, steps: Indices) ?Self {
            const view = self.sliceStep(from, shape, steps);
            return if (view.validView()) view else null;
        }

        /// Returns a new view containing the sub-region starting at `from`
        /// with the given shape and step size. Note that `shape` corresponds
        /// to the region in the original view (i.e. if all steps are 1)
        /// and each component of `steps` must be non-zero. Prefer `slice`
        /// if stepping is not required.
        pub fn sliceStep(self: Self, from: Indices, shape: Indices, steps: Indices) Self {
            var stride = self.stride;
            for (stride) |_, i| {
                stride[i] *= steps[i];
            }
            var result_shape: Indices = undefined;
            for (result_shape) |_, i| {
                result_shape[i] = (shape[i] + steps[i] - 1) / steps[i];
            }
            return Self{
                .items = self.items,
                .shape = result_shape,
                .stride = stride,
                .offset = @intCast(IndexType, self.sliceIndex(from)),
            };
        }


        /// creates a new view whose `dims` inner dimensions creating a sliding window
        /// over the `dims` inner-most dimensions of `self`. The strides of the window
        /// dimensions are copied from the corresponding dimensions of `self`.
        /// Asserts `dims` < `num_dims`
        pub fn slidingWindow(
            self: Self,
            comptime dims: usize,
            window_shape: [dims]IndexType,
        ) StridedArrayViewIdx(T, dims + num_dims, IndexType) {
            std.debug.assert(dims <= num_dims);

            const total_dims = dims + num_dims;
            var shape: [total_dims]IndexType = undefined;
            // copy shape from dimensions we're not sliding along
            std.mem.copy(IndexType, shape[0 .. num_dims - dims], self.shape[0 .. num_dims - dims]);
            // reduce shape size in directions we slide along
            for (shape[num_dims - dims .. num_dims]) |*s, i| {
                s.* = self.shape[i + num_dims - dims] - window_shape[i] + 1;
            }
            std.mem.copy(IndexType, shape[num_dims..], window_shape[0..]);

            var stride: [total_dims]StrideType = undefined;
            // copy stride for the original dimensions
            std.mem.copy(StrideType, stride[0..num_dims], self.stride[0..]);
            // copy strides into corresponding window dimensions
            for (stride[num_dims..]) |*s, i| {
                s.* = self.stride[num_dims - dims + i];
            }
            return StridedArrayViewIdx(T, dims + num_dims, IndexType){
                .items = self.items,
                .stride = stride,
                .shape = shape,
                .offset = self.offset,
            };
        }
    };
}

const TestArrayView = StridedArrayView(u8, 3);
var one_to_23 = [24]TestArrayView.EltType{
    // zig fmt: off
     0,  1,  2,  3,  4,  5,  6,  7,
     8,  9, 10, 11, 12, 13, 14, 15,
    16, 17, 18, 19, 20, 21, 22, 23,
    // zig fmt: on
};

const testing = std.testing;

test {
    std.testing.refAllDeclsRecursive(@This());
    std.testing.refAllDeclsRecursive(TestArrayView);
}

test "strided_array refAllDecls" {
    std.testing.refAllDecls(@This());
}


test "StridedArrayView.strideOfShapePacked()" {
    const shape = TestArrayView.Indices{ 2, 3, 4 };
    const expected = TestArrayView.Stride{ 12, 4, 1 };
    try testing.expectEqual(expected, TestArrayView.strideOfShapePacked(shape));
}

test "StridedArrayView.validView()" {
    var array_view = TestArrayView{
        .items = one_to_23[0..],
        .stride = .{ 12, 4, 1 },
        .shape = .{ 2, 3, 4 },
        .offset = 0,
    };
    // differing offsets (along with associated stride/shape)
    try testing.expect(array_view.validView());
    array_view.stride = .{ 12, 4, 2 };
    try testing.expect(!array_view.validView());
    array_view.shape = .{ 2, 3, 2 };
    try testing.expect(array_view.validView());
    array_view.offset = 1;
    try testing.expect(array_view.validView());
    array_view.offset = 2;
    try testing.expect(!array_view.validView());
    array_view.offset = 3;
    try testing.expect(!array_view.validView());
    array_view.offset = 4;
    try testing.expect(!array_view.validView());
    array_view.shape = .{ 2, 2, 2 };
    array_view.offset = 1;
    try testing.expect(array_view.validView());
    array_view.offset = 2;
    try testing.expect(array_view.validView());
    array_view.offset = 3;
    try testing.expect(array_view.validView());
    array_view.offset = 4;
    try testing.expect(array_view.validView());
    array_view.offset = 5;
    try testing.expect(array_view.validView());
    array_view.offset = 6;
    try testing.expect(!array_view.validView());

    // overlapping window
    array_view.offset = 4;
    array_view.stride = .{ 4, 1, 1 };
    array_view.shape = .{ 5, 3, 2 };
    try testing.expect(array_view.validView());
    array_view.offset = 5;
    try testing.expect(!array_view.validView());

    // overlapping but not unit
    array_view.offset = 0;
    array_view.stride = .{ 4, 2, 1 };
    array_view.shape = .{ 5, 3, 3 };
    try testing.expect(array_view.validView());
    array_view.offset = 1;
    try testing.expect(array_view.validView());
    array_view.offset = 2;
    try testing.expect(!array_view.validView());

    // zero size is not valid
    array_view.offset = 0;
    array_view.shape = .{ 0, 3, 4 };
    array_view.stride = .{ 12, 4, 1 };
    try testing.expect(!array_view.validView());
}

test "StridedArrayView.isValid()" {
    var array_view = TestArrayView{
        .items = one_to_23[0..],
        .stride = .{ 12, 4, 1 },
        .shape = .{ 2, 3, 4 },
        .offset = 0,
    };
    try testing.expect(array_view.isValid(.{ 1, 2, 3 }));
    try testing.expect(array_view.isValid(.{ 0, 0, 0 }));
    try testing.expect(array_view.isValid(.{ 1, 1, 1 }));
    try testing.expect(!array_view.isValid(.{ 2, 2, 3 }));
    try testing.expect(!array_view.isValid(.{ 1, 3, 3 }));
    try testing.expect(!array_view.isValid(.{ 1, 2, 4 }));

    // overlapping window
    array_view.stride = .{ 4, 1, 1 };
    array_view.shape = .{ 6, 3, 2 };
    try testing.expect(array_view.isValid(.{ 4, 2, 1 }));
    array_view.offset = 4;
    array_view.shape = .{ 5, 3, 2 };
    try testing.expect(array_view.isValid(.{ 4, 2, 1 }));
}

test "StridedArrayView.strideOrdering()" {
    var array_view = TestArrayView{
        .items = one_to_23[0..],
        .stride = .{ 12, 4, 1 },
        .shape = .{ 2, 3, 4 },
        .offset = 0,
    };

    try testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, &array_view.strideOrdering());
    array_view.transpose(0, 1);
    try testing.expectEqualSlices(usize, &.{ 1, 0, 2 }, &array_view.strideOrdering());
    array_view.transpose(0, 1);
    array_view.transpose(1, 2);
    try testing.expectEqualSlices(usize, &.{ 0, 2, 1 }, &array_view.strideOrdering());
    array_view.transpose(1, 2);
    array_view.transpose(0, 2);
    try testing.expectEqualSlices(usize, &.{ 2, 1, 0 }, &array_view.strideOrdering());

    array_view.stride = .{ 4, 1, 1 };
    array_view.shape = .{ 6, 3, 2 };

    try testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, &array_view.strideOrdering());
    array_view.transpose(0, 1);
    try testing.expectEqualSlices(usize, &.{ 1, 0, 2 }, &array_view.strideOrdering());
    array_view.transpose(0, 1);
    array_view.transpose(1, 2);
    try testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, &array_view.strideOrdering());
    array_view.transpose(1, 2);
    array_view.transpose(0, 2);
    try testing.expectEqualSlices(usize, &.{ 2, 0, 1 }, &array_view.strideOrdering());

    // overlapping but not unit
    array_view.offset = 0;
    array_view.stride = .{ 4, 2, 1 };
    array_view.shape = .{ 5, 3, 3 };
    try testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, &array_view.strideOrdering());
    array_view.transpose(0, 1);
    try testing.expectEqualSlices(usize, &.{ 1, 0, 2 }, &array_view.strideOrdering());
    array_view.transpose(0, 1);
    array_view.transpose(1, 2);
    try testing.expectEqualSlices(usize, &.{ 0, 2, 1 }, &array_view.strideOrdering());
    array_view.transpose(1, 2);
    array_view.transpose(0, 2);
    try testing.expectEqualSlices(usize, &.{ 2, 1, 0 }, &array_view.strideOrdering());
}

const ForAllSymmetries = @import("test_utils.zig").ForAllSymmetries;

test "StridedArrayView.viewOverlapping()" {
    var array_view = TestArrayView{
        .items = one_to_23[0..],
        .stride = .{ 12, 4, 1 },
        .shape = .{ 2, 3, 4 },
        .offset = 0,
    };

    const tests = struct {
        fn overlap(ctx: void, av: TestArrayView) !void {
            _ = ctx;
            try testing.expect(av.viewOverlapping(av.strideOrdering()));
        }
        fn noOverlap(ctx: void, av: TestArrayView) !void {
            _ = ctx;
            try testing.expect(!av.viewOverlapping(av.strideOrdering()));
        }
    };
    const no_overlap = ForAllSymmetries(void, TestArrayView, tests.noOverlap){ .ctx = .{} };
    const overlap = ForAllSymmetries(void, TestArrayView, tests.overlap){ .ctx = .{} };

    try no_overlap.run(&array_view);

    // overlapping window
    array_view.offset = 4;
    array_view.stride = .{ 4, 1, 1 };
    array_view.shape = .{ 5, 3, 2 };

    try overlap.run(&array_view);

    // overlapping but not unit
    array_view.offset = 0;
    array_view.stride = .{ 4, 2, 1 };
    array_view.shape = .{ 5, 3, 3 };

    try overlap.run(&array_view);
}

test "StridedArrayView.coordOfSliceIndex()" {
    var array_view = TestArrayView{
        .items = one_to_23[0..],
        .stride = .{ 12, 4, 1 },
        .shape = .{ 2, 3, 4 },
        .offset = 0,
    };

    try testing.expectEqual(TestArrayView.Indices{ 0, 0, 0 }, try array_view.coordOfSliceIndex(0));
    try testing.expectEqual(TestArrayView.Indices{ 0, 0, 3 }, try array_view.coordOfSliceIndex(3));
    try testing.expectEqual(TestArrayView.Indices{ 1, 2, 0 }, try array_view.coordOfSliceIndex(20));
    try testing.expectEqual(TestArrayView.Indices{ 1, 1, 2 }, try array_view.coordOfSliceIndex(18));
    try testing.expectEqual(TestArrayView.Indices{ 1, 2, 3 }, try array_view.coordOfSliceIndex(23));

    // transposed
    array_view.transpose(1, 2);
    try testing.expectEqual(TestArrayView.Indices{ 0, 0, 0 }, try array_view.coordOfSliceIndex(0));
    try testing.expectEqual(TestArrayView.Indices{ 0, 1, 0 }, try array_view.coordOfSliceIndex(1));
    try testing.expectEqual(TestArrayView.Indices{ 0, 2, 0 }, try array_view.coordOfSliceIndex(2));
    try testing.expectEqual(TestArrayView.Indices{ 0, 3, 0 }, try array_view.coordOfSliceIndex(3));
    try testing.expectEqual(TestArrayView.Indices{ 1, 0, 2 }, try array_view.coordOfSliceIndex(20));
    try testing.expectEqual(TestArrayView.Indices{ 1, 2, 1 }, try array_view.coordOfSliceIndex(18));
    try testing.expectEqual(TestArrayView.Indices{ 1, 3, 2 }, try array_view.coordOfSliceIndex(23));

    // overlapping window
    array_view.offset = 4;
    array_view.stride = .{ 4, 1, 1 };
    array_view.shape = .{ 5, 3, 2 };
    try testing.expectError(ViewError.OverlappingElementsUnsupported, array_view.coordOfSliceIndex(4));

    // transposed
    array_view.transpose(1, 2);
    try testing.expectError(ViewError.OverlappingElementsUnsupported, array_view.coordOfSliceIndex(4));

    // overlapping but not unit
    array_view.offset = 0;
    array_view.stride = .{ 4, 2, 1 };
    array_view.shape = .{ 5, 3, 3 };
    try testing.expectError(ViewError.OverlappingElementsUnsupported, array_view.coordOfSliceIndex(4));
}
