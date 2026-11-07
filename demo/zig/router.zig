// router.zig -- tiny method+path router, Zig port of demo/lib/router.mjs.
// Patterns are slices of segments like &.{ "contacts", ":id", "edit" };
// each ":name" segment matches one path component and ends up in the
// params map passed to the handler.

const std = @import("std");

pub fn Router(comptime Ctx: type) type {
    return struct {
        pub const Handler = *const fn (*Ctx) anyerror!void;

        pub const Route = struct {
            method: []const u8,
            pattern: []const []const u8,
            handler: Handler,
        };

        routes: []const Route,

        pub fn splitPath(allocator: std.mem.Allocator, path: []const u8) ![][]const u8 {
            var out: std.ArrayList([]const u8) = .empty;
            var it = std.mem.splitScalar(u8, path, '/');
            while (it.next()) |seg| {
                if (seg.len != 0) try out.append(allocator, seg);
            }
            return out.toOwnedSlice(allocator);
        }

        fn matchOne(pattern: []const []const u8, segs: []const []const u8, params: *std.StringHashMap([]const u8)) !bool {
            if (pattern.len != segs.len) return false;
            for (pattern, segs) |p, s| {
                if (p.len > 0 and p[0] == ':') {
                    try params.put(p[1..], s);
                } else if (!std.mem.eql(u8, p, s)) {
                    return false;
                }
            }
            return true;
        }

        /// Try every route in registration order; on the first match, fill
        /// `params` and call its handler. Returns true if something matched.
        pub fn dispatch(
            self: @This(),
            allocator: std.mem.Allocator,
            method: []const u8,
            segs: []const []const u8,
            params: *std.StringHashMap([]const u8),
            ctx: *Ctx,
        ) !bool {
            for (self.routes) |r| {
                if (!std.mem.eql(u8, r.method, method)) continue;
                params.clearRetainingCapacity();
                if (try matchOne(r.pattern, segs, params)) {
                    _ = allocator;
                    try r.handler(ctx);
                    return true;
                }
            }
            return false;
        }
    };
}
