# zig-strided-arrays

A library implementing strided arrays for [Zig](https://ziglang.org).

#### Features

Strided arrays allow flexible manipulation of and iteration over an underlying slice. This library provides the `StridedArrayView(T, n)` generic type, which is an `n`-dimensional view of a `[]T`. The `StridedArrayView(T, n)` type provides get/set helpers with access by coordinate, iterators over the data 'in view' (in row-major order), utilities to produce sub-views (e.g. with `slice()`), and `flip()` and `transpose()` for cheap (i.e. without a copy) logical reordering of data.

The strides of a view can be manipulated to achieve a range of effects; currently there is only one 'more advanced' helper for manipulating strides, `slidingWindow()`, which produces a (higher dimensional) view where the inner-most dimensions act as a sliding window over the original view data. If there are utilities you would like to see included please raise an issue or submit a pull request.

#### Limitations

The current implementation measures strides in terms of the data type of the underlying slice (not `u8`s), so you can't add exactly `n` bytes of padding to each row of a 2-dimensional array for example (unless the size of the array's data type divides `n`).

#### Contributing

Feel free to open issues or submit pull requests if you think something can be improved, or there is other functionality you think would be useful (e.g. helpers for manipulating strides). The current API might be a bit crufty as well, so feel free to suggest improvements.
