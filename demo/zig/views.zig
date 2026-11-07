// views.zig -- near line-for-line port of demo/views/contacts/*.eta.
// Each view writes HTML straight to the given Io.Writer -- no intermediate
// string building, unlike the other ports, since Zig compiles to native
// code and the writer is already buffered.

const std = @import("std");
const Io = std.Io;
const contacts = @import("contacts.zig");
const Contact = contacts.Contact;

pub fn esc(w: *Io.Writer, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '&' => try w.writeAll("&amp;"),
            '<' => try w.writeAll("&lt;"),
            '>' => try w.writeAll("&gt;"),
            '"' => try w.writeAll("&quot;"),
            '\'' => try w.writeAll("&#39;"),
            else => try w.writeByte(c),
        }
    }
}

pub fn writeRow(w: *Io.Writer, c: Contact) !void {
    try w.print("<div class=\"row\" id=\"c-{d}\">", .{c.id});
    try w.writeAll("<div class=\"cell\">");
    try esc(w, c.name);
    try w.writeAll("</div><div class=\"cell\">");
    try esc(w, c.email);
    try w.writeAll("</div><div class=\"cell\">");
    try esc(w, c.phone);
    try w.writeAll("</div><div class=\"actions\">");
    try w.print("<button fx-action=\"/contacts/{d}/edit\" fx-target=\"#c-{d}\">edit</button>", .{ c.id, c.id });
    try w.print(
        "<button class=\"danger\" fx-action=\"/contacts/{d}\" fx-method=\"DELETE\" fx-target=\"#c-{d}\" " ++
            "on-fx:config=\"cfg.confirm = () =&gt; confirm(&#39;Delete this contact?&#39;)\">&times;</button>",
        .{ c.id, c.id },
    );
    try w.writeAll("</div></div>");
}

pub fn writeList(w: *Io.Writer, cs: []const Contact) !void {
    try w.writeAll("<div id=\"contacts-list\">");
    if (cs.len == 0) {
        try w.writeAll("<div class=\"row empty\">No matches.</div>");
    } else {
        for (cs) |c| try writeRow(w, c);
    }
    try w.writeAll("</div>");
}

pub fn writeEdit(w: *Io.Writer, c: Contact) !void {
    try w.print("<form class=\"row editing\" id=\"c-{d}\" fx-action=\"/contacts/{d}\" fx-method=\"PUT\">", .{ c.id, c.id });

    try w.writeAll("<div class=\"cell\"><input name=\"name\" value=\"");
    try esc(w, c.name);
    try w.writeAll("\" autofocus required></div>");

    try w.writeAll("<div class=\"cell\"><input name=\"email\" value=\"");
    try esc(w, c.email);
    try w.writeAll("\" type=\"email\" required></div>");

    try w.writeAll("<div class=\"cell\"><input name=\"phone\" value=\"");
    try esc(w, c.phone);
    try w.writeAll("\" type=\"tel\" required></div>");

    try w.print(
        "<div class=\"actions\"><button live=\"this.disabled = !this.form.checkValidity()\">save</button>" ++
            "<button type=\"button\" fx-action=\"/contacts/{d}\" fx-target=\"#c-{d}\">cancel</button></div></form>",
        .{ c.id, c.id },
    );
}

const PAGE_HEAD =
    \\<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
    \\<title>Contacts - fixi demo</title>
    \\<script src="/dist/the-fixi-project.js"></script>
    \\<link rel="stylesheet" href="/css/layout.css">
    \\<link rel="stylesheet" href="/css/contacts.css">
    \\</head><body><header class="nav"><a href="/">&larr; demo index</a></header>
    \\<h1 xmlns:on-fx="http://www.w3.org/1999/xhtml">&#x1F4D2; Contacts</h1>
    \\<div class="contacts"><div class="toolbar">
    \\<input id="search" name="q" type="search" placeholder="Search name, email, phone&hellip;"
    \\       autofocus fx-action="/contacts" fx-trigger="search" fx-target="#contacts-list"
    \\       fx-swap="morph" on-input="await debounce(180); trigger('search')">
    \\<form class="new" fx-action="/contacts" fx-method="POST" fx-target="#contacts-list"
    \\      fx-swap="morph" on-fx:swapped="this.reset(); q('first input').focus()">
    \\    <input name="name"  placeholder="New name" required>
    \\    <input name="email" placeholder="email"    type="email" required>
    \\    <input name="phone" placeholder="phone"    type="tel"   required>
    \\    <button live="this.disabled = !this.form.checkValidity()">+ Add</button>
    \\</form>
    \\</div>
    \\<div class="row header"><div>Name</div><div>Email</div><div>Phone</div><div></div></div>
;

const PAGE_TAIL = "</div></body></html>";

pub fn writePage(w: *Io.Writer, cs: []const Contact) !void {
    try w.writeAll(PAGE_HEAD);
    try writeList(w, cs);
    try w.writeAll(PAGE_TAIL);
}
