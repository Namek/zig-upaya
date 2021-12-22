// const std = @import("std");
// const mem = std.mem;
// const Allocator = mem.Allocator;


// pub fn ScratchAllocator(comptime T: type) type {
//     return struct {
//         const Self = @This();

//         backup_allocator: T,
//         end_index: usize,
//         buffer: []u8,

//         pub fn init (backup_allocator: T) @This() {

//             const scratch_buffer = backup_allocator.allocator().alloc(u8, 2 * 1024 * 1024) catch unreachable;
           
//             return .{
//                 .backup_allocator = backup_allocator,
//                 .end_index = 0,
//                 .buffer = scratch_buffer,
//             };
//         }

//         pub fn allocator(self: *Self) Allocator {
//             return Allocator.init(self, alloc, Allocator.NoResize(Self).noResize, Allocator.PanicFree(Self).noOpFree);
//         }

//         pub fn alloc(self: *Self, n:usize, ptr_align:u29, len_align:u29, ret_addr:usize) Allocator.Error![]u8 {
//             const a = self.allocator();
//             const addr = @ptrToInt(self.buffer.ptr) + self.end_index;
//             const adjusted_addr = mem.alignForward(addr, ptr_align);
//             const adjusted_index = self.end_index + (adjusted_addr - addr);
//             const new_end_index = adjusted_index + n;



//         }




//     };
// }


// pub const ScratchAllocatorOld = struct {

//     allocator: *Allocator,
//     backup_allocator: *Allocator,
//     end_index: usize,
//     buffer: []u8,

//     const Self = @This();

//     pub fn init(allocator: Allocator) ScratchAllocator {
//         const scratch_buffer = allocator.alloc(u8, 2 * 1024 * 1024) catch unreachable;

//         return ScratchAllocator{
//             .allocator = Allocator.init(&allocator, alloc, Allocator.NoResize(Allocator).noResize, Allocator.PanicFree(Allocator).noOpFree),
//             .backup_allocator = allocator,
//             .buffer = scratch_buffer,
//             .end_index = 0,
//         };
//     }

//     fn alloc(ptr: *Allocator, n: usize, ptr_align: u29, len_align: u29, ret_addr: usize) Allocator.Error![]u8 {
//         const self = @fieldParentPtr(ScratchAllocator, "allocator", &ptr);
//         const addr = @ptrToInt(self.buffer.ptr) + self.end_index;
//         const adjusted_addr = mem.alignForward(addr, ptr_align);
//         const adjusted_index = self.end_index + (adjusted_addr - addr);
//         const new_end_index = adjusted_index + n;

//         if (new_end_index > self.buffer.len) {
//             // if more memory is requested then we have in our buffer leak like a sieve!
//             if (n > self.buffer.len) {
//                 std.log.err("\n---------\nwarning: tmp allocated more than is in our temp allocator. This memory WILL leak!\n--------\n", .{});
                
//                 return self.allocator.alloc(self, n, ptr_align, len_align, ret_addr);
//             }

//             const result = self.buffer[0..n];
//             self.end_index = n;
//             return result;
//         }
//         const result = self.buffer[adjusted_index..new_end_index];
//         self.end_index = new_end_index;

//         return result;
//     }
// };

// test "scratch allocator" {
//     var allocator_instance = ScratchAllocator.init(@import("mem.zig").allocator);

//     var slice = try allocator_instance.allocator.alloc(*i32, 100);
//     std.testing.expect(slice.len == 100);

//     _ = try allocator_instance.allocator.create(i32);

//     slice = try allocator_instance.allocator.realloc(slice, 20000);
//     std.testing.expect(slice.len == 20000);
//     allocator_instance.allocator.free(slice);
// }
