// util.zig -- request parsing and response helpers, Zig port of
// demo/lib/util.mjs.

const std = @import("std");
const Io = std.Io;

pub fn urlDecode(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < s.len) {
        const c = s[i];
        if (c == '+') {
            try out.append(allocator, ' ');
            i += 1;
        } else if (c == '%' and i + 2 < s.len) {
            const byte = std.fmt.parseInt(u8, s[i + 1 .. i + 3], 16) catch {
                try out.append(allocator, c);
                i += 1;
                continue;
            };
            try out.append(allocator, byte);
            i += 3;
        } else {
            try out.append(allocator, c);
            i += 1;
        }
    }
    return out.toOwnedSlice(allocator);
}

pub const Form = std.StringHashMap([]const u8);

pub fn formGet(form: *const Form, key: []const u8) []const u8 {
    return form.get(key) orelse "";
}

/// Parse "a=b&c=d" into a Form. Keys/values are urlDecode'd into `allocator`.
pub fn parseForm(allocator: std.mem.Allocator, s: []const u8) !Form {
    var form = Form.init(allocator);
    if (s.len == 0) return form;
    var pairs = std.mem.splitScalar(u8, s, '&');
    while (pairs.next()) |pair| {
        if (pair.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, pair, '=');
        if (eq) |idx| {
            const k = try urlDecode(allocator, pair[0..idx]);
            const v = try urlDecode(allocator, pair[idx + 1 ..]);
            try form.put(k, v);
        } else {
            const k = try urlDecode(allocator, pair);
            try form.put(k, "");
        }
    }
    return form;
}

/// Extract the boundary token from a "multipart/form-data; boundary=XXX"
/// Content-Type header value, stripping surrounding quotes if present.
pub fn mpBoundary(content_type: []const u8) ?[]const u8 {
    const marker = "boundary=";
    const idx = std.mem.indexOf(u8, content_type, marker) orelse return null;
    var rest = content_type[idx + marker.len ..];
    if (std.mem.indexOfScalar(u8, rest, ';')) |semi| rest = rest[0..semi];
    if (rest.len >= 2 and rest[0] == '"') {
        return std.mem.trim(u8, rest, "\"");
    }
    return std.mem.trim(u8, rest, " \t");
}

/// Minimal multipart/form-data parser for text fields.
pub fn parseMultipart(allocator: std.mem.Allocator, body: []const u8, boundary: []const u8) !Form {
    var form = Form.init(allocator);
    var marker_buf: [256]u8 = undefined;
    const marker = try std.fmt.bufPrint(&marker_buf, "--{s}", .{boundary});

    var parts = std.mem.splitSequence(u8, body, marker);
    while (parts.next()) |part| {
        const hdr_end = std.mem.indexOf(u8, part, "\r\n\r\n") orelse continue;
        const headers = part[0..hdr_end];
        var content = part[hdr_end + 4 ..];
        if (std.mem.endsWith(u8, content, "\r\n")) content = content[0 .. content.len - 2];

        const name_marker = "name=\"";
        const name_start = std.mem.indexOf(u8, headers, name_marker) orelse continue;
        const after_marker = headers[name_start + name_marker.len ..];
        const name_end = std.mem.indexOfScalar(u8, after_marker, '"') orelse continue;
        const name = after_marker[0..name_end];

        try form.put(try allocator.dupe(u8, name), try allocator.dupe(u8, content));
    }
    return form;
}

// --- HTTP response helpers ----------------------------------------------

pub fn sendHtml(w: *Io.Writer, html: []const u8) !void {
    try w.print(
        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{html.len},
    );
    try w.writeAll(html);
    try w.flush();
}

pub fn sendNoContent(w: *Io.Writer) !void {
    try w.writeAll("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n");
    try w.flush();
}

pub fn sendNotFound(w: *Io.Writer) !void {
    const body = "not found";
    try w.print(
        "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{body.len},
    );
    try w.writeAll(body);
    try w.flush();
}

pub fn mimeFor(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    if (std.mem.eql(u8, ext, ".html")) return "text/html; charset=utf-8";
    if (std.mem.eql(u8, ext, ".js")) return "text/javascript; charset=utf-8";
    if (std.mem.eql(u8, ext, ".css")) return "text/css; charset=utf-8";
    if (std.mem.eql(u8, ext, ".json")) return "application/json; charset=utf-8";
    if (std.mem.eql(u8, ext, ".map")) return "application/json; charset=utf-8";
    return "application/octet-stream";
}

pub fn sendFile(allocator: std.mem.Allocator, io: Io, w: *Io.Writer, path: []const u8) !void {
    var file = Io.Dir.cwd().openFile(io, path, .{}) catch {
        return sendNotFound(w);
    };
    defer file.close(io);

    var read_buf: [8192]u8 = undefined;
    var fr = file.reader(io, &read_buf);
    const data = try fr.interface.allocRemaining(allocator, .unlimited);

    try w.print(
        "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{ mimeFor(path), data.len },
    );
    try w.writeAll(data);
    try w.flush();
}
