// server.zig -- Zig port of demo/server.mjs for the Contacts demo.
// Each accepted connection is handled on its own OS thread (std.Thread):
// blocking reads/writes on one connection never stall another, and Zig's
// native compilation means there's no interpreter overhead to fight in
// the first place.
//
// Run:  zig run demo/zig/server.zig -- [port]   (or: ./run.sh [port])

const std = @import("std");
const Io = std.Io;

const contacts = @import("contacts.zig");
const views = @import("views.zig");
const util = @import("util.zig");
const router_mod = @import("router.zig");

const Ctx = struct {
    allocator: std.mem.Allocator,
    io: Io,
    w: *Io.Writer,
    params: std.StringHashMap([]const u8),
    query: util.Form,
    form: util.Form,

    fn paramId(ctx: *Ctx) ?u32 {
        const s = ctx.params.get("id") orelse return null;
        return std.fmt.parseInt(u32, s, 10) catch null;
    }
};

const Router = router_mod.Router(Ctx);

// --- route handlers --------------------------------------------------------

fn renderPage(ctx: *Ctx) !void {
    const cs = try contacts.all(ctx.allocator, ctx.io);
    var aw = Io.Writer.Allocating.init(ctx.allocator);
    defer aw.deinit();
    try views.writePage(&aw.writer, cs);
    try util.sendHtml(ctx.w, aw.writer.buffered());
}

fn renderList(ctx: *Ctx, cs: []const contacts.Contact) !void {
    var aw = Io.Writer.Allocating.init(ctx.allocator);
    defer aw.deinit();
    try views.writeList(&aw.writer, cs);
    try util.sendHtml(ctx.w, aw.writer.buffered());
}

fn renderRow(ctx: *Ctx, c: contacts.Contact) !void {
    var aw = Io.Writer.Allocating.init(ctx.allocator);
    defer aw.deinit();
    try views.writeRow(&aw.writer, c);
    try util.sendHtml(ctx.w, aw.writer.buffered());
}

fn hContactsPage(ctx: *Ctx) !void {
    try renderPage(ctx);
}

fn hContactsList(ctx: *Ctx) !void {
    const q = util.formGet(&ctx.query, "q");
    const cs = try contacts.search(ctx.allocator, ctx.io, q);
    try renderList(ctx, cs);
}

fn hContactsAdd(ctx: *Ctx) !void {
    _ = try contacts.add(
        ctx.allocator,
        ctx.io,
        util.formGet(&ctx.form, "name"),
        util.formGet(&ctx.form, "email"),
        util.formGet(&ctx.form, "phone"),
    );
    const cs = try contacts.all(ctx.allocator, ctx.io);
    try renderList(ctx, cs);
}

fn hContactRow(ctx: *Ctx) !void {
    const id = ctx.paramId() orelse return util.sendNotFound(ctx.w);
    const c = (try contacts.find(ctx.allocator, ctx.io, id)) orelse return util.sendNotFound(ctx.w);
    try renderRow(ctx, c);
}

fn hContactEdit(ctx: *Ctx) !void {
    const id = ctx.paramId() orelse return util.sendNotFound(ctx.w);
    const c = (try contacts.find(ctx.allocator, ctx.io, id)) orelse return util.sendNotFound(ctx.w);
    var aw = Io.Writer.Allocating.init(ctx.allocator);
    defer aw.deinit();
    try views.writeEdit(&aw.writer, c);
    try util.sendHtml(ctx.w, aw.writer.buffered());
}

fn hContactUpdate(ctx: *Ctx) !void {
    const id = ctx.paramId() orelse return util.sendNotFound(ctx.w);
    const c = (try contacts.update(
        ctx.allocator,
        ctx.io,
        id,
        util.formGet(&ctx.form, "name"),
        util.formGet(&ctx.form, "email"),
        util.formGet(&ctx.form, "phone"),
    )) orelse return util.sendNotFound(ctx.w);
    try renderRow(ctx, c);
}

fn hContactDelete(ctx: *Ctx) !void {
    const id = ctx.paramId() orelse return util.sendNotFound(ctx.w);
    _ = contacts.remove(ctx.io, id);
    try util.sendNoContent(ctx.w);
}

const routes = [_]Router.Route{
    .{ .method = "GET", .pattern = &.{"contacts.html"}, .handler = hContactsPage },
    .{ .method = "GET", .pattern = &.{"contacts"}, .handler = hContactsList },
    .{ .method = "POST", .pattern = &.{"contacts"}, .handler = hContactsAdd },
    .{ .method = "GET", .pattern = &.{ "contacts", ":id" }, .handler = hContactRow },
    .{ .method = "GET", .pattern = &.{ "contacts", ":id", "edit" }, .handler = hContactEdit },
    .{ .method = "PUT", .pattern = &.{ "contacts", ":id" }, .handler = hContactUpdate },
    .{ .method = "DELETE", .pattern = &.{ "contacts", ":id" }, .handler = hContactDelete },
};

const router: Router = .{ .routes = &routes };

// --- static assets (css, the fixi client script) --------------------------

// Assumes the process's cwd is demo/zig/ (run.sh `cd`s there before
// running), same convention as demo/tcl/run.sh and demo/picolisp/run.sh.
// ".." is demo/, "../.." is the repo root.
fn serveStatic(allocator: std.mem.Allocator, io: Io, w: *Io.Writer, path: []const u8) !void {
    const rel = if (std.mem.startsWith(u8, path, "/dist/"))
        try std.fmt.allocPrint(allocator, "../..{s}", .{path})
    else if (std.mem.eql(u8, path, "/"))
        try allocator.dupe(u8, "../public/index.html")
    else
        try std.fmt.allocPrint(allocator, "../public{s}", .{path});
    try util.sendFile(allocator, io, w, rel);
}

// --- connection handling -----------------------------------------------

fn handleConn(io: Io, stream: Io.net.Stream) void {
    defer stream.close(io);

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const allocator = arena_state.allocator();

    var read_buf: [1 << 16]u8 = undefined;
    var sr = stream.reader(io, &read_buf);
    var out_buf: [1 << 16]u8 = undefined;
    var sw = stream.writer(io, &out_buf);
    const w = &sw.interface;

    processRequest(allocator, io, &sr.interface, w) catch |err| switch (err) {
        error.EndOfStream, error.ReadFailed, error.WriteFailed => {},
        else => std.debug.print("request error: {s}\n", .{@errorName(err)}),
    };
}

fn processRequest(allocator: std.mem.Allocator, io: Io, r: *Io.Reader, w: *Io.Writer) !void {
    // `takeDelimiterExclusive` returns a slice into the reader's internal
    // buffer, invalidated by the *next* take/peek/fill call -- every line
    // must be copied out before reading the next one.
    const req_line = try allocator.dupe(u8, try takeLineTrimmed(r));
    var parts = std.mem.splitScalar(u8, req_line, ' ');
    const method = parts.next() orelse return;
    const full = parts.next() orelse return;

    var headers = std.StringHashMap([]const u8).init(allocator);
    while (true) {
        const line = try allocator.dupe(u8, try takeLineTrimmed(r));
        if (line.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = try std.ascii.allocLowerString(allocator, std.mem.trim(u8, line[0..colon], " "));
        const value = std.mem.trim(u8, line[colon + 1 ..], " ");
        try headers.put(name, value);
    }

    var path = full;
    var query_str: []const u8 = "";
    if (std.mem.indexOfScalar(u8, full, '?')) |qpos| {
        path = full[0..qpos];
        query_str = full[qpos + 1 ..];
    }
    const query = try util.parseForm(allocator, query_str);

    var len: usize = 0;
    if (headers.get("content-length")) |cl| len = std.fmt.parseInt(usize, cl, 10) catch 0;

    var form = util.Form.init(allocator);
    if (len > 0) {
        const body = try r.take(len);
        const ctype = headers.get("content-type") orelse "";
        if (std.mem.indexOf(u8, ctype, "multipart/form-data") != null) {
            if (util.mpBoundary(ctype)) |b| form = try util.parseMultipart(allocator, body, b);
        } else {
            form = try util.parseForm(allocator, body);
        }
    }

    var ctx = Ctx{
        .allocator = allocator,
        .io = io,
        .w = w,
        .params = std.StringHashMap([]const u8).init(allocator),
        .query = query,
        .form = form,
    };

    const segs = try Router.splitPath(allocator, path);
    const matched = try router.dispatch(allocator, method, segs, &ctx.params, &ctx);
    if (!matched) {
        if (std.mem.eql(u8, method, "GET")) {
            try serveStatic(allocator, io, w, path);
        } else {
            try util.sendNotFound(w);
        }
    }
}

fn takeLineTrimmed(r: *Io.Reader) ![]const u8 {
    // `takeDelimiterExclusive` leaves the delimiter itself unconsumed in
    // the stream (only `*Inclusive` tosses it), so use Inclusive and trim
    // both the '\n' and a preceding '\r' ourselves.
    const line = try r.takeDelimiterInclusive('\n');
    return std.mem.trimEnd(u8, line, "\r\n");
}

// --- worker pool ------------------------------------------------------
//
// A fixed number of OS threads, spawned once at startup, pull accepted
// connections off a shared queue. This avoids the per-connection
// std.Thread.spawn/teardown cost of the earlier version -- threads are
// created once and reused for the life of the process. (Zig 0.16 has no
// std.Thread.Pool; io.concurrent's Future-based pool exists but leaks
// its Future unless awaited, which doesn't fit a fire-and-forget accept
// loop, so this is a plain hand-rolled mutex+condvar queue instead.)

const POOL_SIZE = 16;

var queue_mutex: Io.Mutex = .init;
var queue_cond: Io.Condition = .init;
var queue: std.ArrayList(Io.net.Stream) = .empty;

fn worker(io: Io) void {
    while (true) {
        queue_mutex.lockUncancelable(io);
        while (queue.items.len == 0) queue_cond.waitUncancelable(io, &queue_mutex);
        // FIFO, not `pop()` (LIFO): under sustained load a stack lets newer
        // connections keep jumping ahead, starving the oldest queued ones
        // until they trip a client-side timeout.
        const stream = queue.orderedRemove(0);
        queue_mutex.unlock(io);
        handleConn(io, stream);
    }
}

// --- main -----------------------------------------------------------------

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    contacts.ensureSeeded(io);

    var it = init.minimal.args.iterate();
    _ = it.next();
    const port: u16 = if (it.next()) |p| std.fmt.parseInt(u16, p, 10) catch 8769 else 8769;

    var addr = try Io.net.IpAddress.parse("0.0.0.0", port);
    var server = try Io.net.IpAddress.listen(&addr, io, .{ .reuse_address = true, .kernel_backlog = 511 });
    defer server.deinit(io);

    for (0..POOL_SIZE) |_| {
        const t = try std.Thread.spawn(.{}, worker, .{io});
        t.detach();
    }

    std.debug.print("Contacts demo (Zig) listening on http://localhost:{d}/contacts.html ({d}-thread pool)\n", .{ port, POOL_SIZE });

    while (true) {
        const stream = server.accept(io) catch continue;
        queue_mutex.lockUncancelable(io);
        queue.append(std.heap.page_allocator, stream) catch {
            queue_mutex.unlock(io);
            stream.close(io);
            continue;
        };
        queue_mutex.unlock(io);
        queue_cond.signal(io);
    }
}
