// contacts.zig -- in-memory contact store, direct port of
// demo/apps/contacts.mjs. Guarded by `mutex` since the server handles
// each connection on its own thread. Zig 0.16 moved synchronization
// primitives under std.Io, so every entry point takes an `io: std.Io`.

const std = @import("std");
const Io = std.Io;

pub const Contact = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
    phone: []const u8,
};

var gpa_state = std.heap.DebugAllocator(.{}){};
const gpa = gpa_state.allocator();

var mutex: Io.Mutex = .init;
var store: std.ArrayList(Contact) = .empty;
var next_id: u32 = 8;

fn seed() void {
    // Every stored string must be gpa-owned (never a string literal) since
    // update/remove unconditionally gpa.free() a contact's fields.
    const seeds = [_]Contact{
        .{ .id = 1, .name = "Lena Park", .email = "lena@example.com", .phone = "555-0101" },
        .{ .id = 2, .name = "Kai Bennett", .email = "kai@example.com", .phone = "555-0102" },
        .{ .id = 3, .name = "Yuki Tanaka", .email = "yuki.tanaka@example.com", .phone = "555-0103" },
        .{ .id = 4, .name = "Priya Sharma", .email = "priya@example.com", .phone = "555-0104" },
        .{ .id = 5, .name = "Diego Ramos", .email = "diego.ramos@example.com", .phone = "555-0105" },
        .{ .id = 6, .name = "Mei Chen", .email = "mei@example.com", .phone = "555-0106" },
        .{ .id = 7, .name = "Olu Adesina", .email = "olu@example.com", .phone = "555-0107" },
    };
    for (seeds) |c| {
        store.append(gpa, .{
            .id = c.id,
            .name = gpa.dupe(u8, c.name) catch unreachable,
            .email = gpa.dupe(u8, c.email) catch unreachable,
            .phone = gpa.dupe(u8, c.phone) catch unreachable,
        }) catch unreachable;
    }
}

var seeded = false;

pub fn ensureSeeded(io: Io) void {
    mutex.lockUncancelable(io);
    defer mutex.unlock(io);
    if (!seeded) {
        seeded = true;
        seed();
    }
}

fn trim(allocator: std.mem.Allocator, s: []const u8, max_len: usize) ![]const u8 {
    const trimmed = std.mem.trim(u8, s, " \t\r\n");
    const clipped = trimmed[0..@min(trimmed.len, max_len)];
    return allocator.dupe(u8, clipped);
}

/// Deep copy: a concurrent update/remove on another thread can gpa.free()
/// a contact's string fields the instant the mutex is released, so the
/// caller (rendering on its own thread, past that point) must never
/// touch store-owned memory. Everything returned here is duplicated
/// into the caller's allocator (typically a per-request arena).
fn dupeContact(allocator: std.mem.Allocator, c: Contact) !Contact {
    return .{
        .id = c.id,
        .name = try allocator.dupe(u8, c.name),
        .email = try allocator.dupe(u8, c.email),
        .phone = try allocator.dupe(u8, c.phone),
    };
}

pub fn all(allocator: std.mem.Allocator, io: Io) ![]Contact {
    mutex.lockUncancelable(io);
    defer mutex.unlock(io);
    var out: std.ArrayList(Contact) = .empty;
    for (store.items) |c| try out.append(allocator, try dupeContact(allocator, c));
    return out.toOwnedSlice(allocator);
}

pub fn find(allocator: std.mem.Allocator, io: Io, id: u32) !?Contact {
    mutex.lockUncancelable(io);
    defer mutex.unlock(io);
    for (store.items) |c| {
        if (c.id == id) return try dupeContact(allocator, c);
    }
    return null;
}

pub fn search(allocator: std.mem.Allocator, io: Io, q: []const u8) ![]Contact {
    mutex.lockUncancelable(io);
    defer mutex.unlock(io);
    if (q.len == 0) {
        var out: std.ArrayList(Contact) = .empty;
        for (store.items) |c| try out.append(allocator, try dupeContact(allocator, c));
        return out.toOwnedSlice(allocator);
    }

    var buf: [256]u8 = undefined;
    const needle = std.ascii.lowerString(buf[0..@min(buf.len, q.len)], q[0..@min(buf.len, q.len)]);

    var out: std.ArrayList(Contact) = .empty;
    for (store.items) |c| {
        if (containsCaseInsensitive(c.name, needle) or
            containsCaseInsensitive(c.email, needle) or
            std.mem.indexOf(u8, c.phone, q) != null)
        {
            try out.append(allocator, try dupeContact(allocator, c));
        }
    }
    return out.toOwnedSlice(allocator);
}

fn containsCaseInsensitive(haystack: []const u8, needle_lower: []const u8) bool {
    if (needle_lower.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle_lower.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle_lower.len], needle_lower)) return true;
    }
    return false;
}

pub fn add(allocator: std.mem.Allocator, io: Io, name: []const u8, email: []const u8, phone: []const u8) !?Contact {
    const n = try trim(gpa, name, 80);
    if (n.len == 0) {
        gpa.free(n);
        return null;
    }
    const e = try trim(gpa, email, 80);
    const p = try trim(gpa, phone, 40);

    mutex.lockUncancelable(io);
    defer mutex.unlock(io);
    const c = Contact{ .id = next_id, .name = n, .email = e, .phone = p };
    next_id += 1;
    try store.append(gpa, c);
    return try dupeContact(allocator, c);
}

pub fn update(allocator: std.mem.Allocator, io: Io, id: u32, name: []const u8, email: []const u8, phone: []const u8) !?Contact {
    mutex.lockUncancelable(io);
    defer mutex.unlock(io);
    for (store.items) |*c| {
        if (c.id != id) continue;
        const n = try trim(gpa, name, 80);
        if (n.len > 0) {
            gpa.free(c.name);
            c.name = n;
        } else {
            gpa.free(n);
        }
        gpa.free(c.email);
        c.email = try trim(gpa, email, 80);
        gpa.free(c.phone);
        c.phone = try trim(gpa, phone, 40);
        return try dupeContact(allocator, c.*);
    }
    return null;
}

pub fn remove(io: Io, id: u32) bool {
    mutex.lockUncancelable(io);
    defer mutex.unlock(io);
    for (store.items, 0..) |c, i| {
        if (c.id != id) continue;
        gpa.free(c.name);
        gpa.free(c.email);
        gpa.free(c.phone);
        _ = store.orderedRemove(i);
        return true;
    }
    return false;
}
