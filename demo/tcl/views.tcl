# views.tcl -- near line-for-line port of demo/views/contacts/*.eta,
# built with plain string templates and [esc] for escaping.

source [file join [file dirname [info script]] contacts.tcl]

proc viewRow {c} {
    set id [dict get $c id]
    return [subst {<div class="row" id="c-$id">
    <div class="cell">[esc [dict get $c name]]</div>
    <div class="cell">[esc [dict get $c email]]</div>
    <div class="cell">[esc [dict get $c phone]]</div>
    <div class="actions">
        <button fx-action="/contacts/$id/edit" fx-target="#c-$id">edit</button>
        <button class="danger"
                fx-action="/contacts/$id"
                fx-method="DELETE"
                fx-target="#c-$id"
                on-fx:config="cfg.confirm = () =&gt; confirm('Delete this contact?')">&times;</button>
    </div>
</div>
}]
}

proc viewList {contacts} {
    set rows ""
    foreach c $contacts { append rows [viewRow $c] }
    if {[llength $contacts] == 0} {
        set rows {<div class="row empty">No matches.</div>}
    }
    return "<div id=\"contacts-list\">\n$rows</div>\n"
}

proc viewEdit {c} {
    set id [dict get $c id]
    return [subst {<form class="row editing" id="c-$id"
      fx-action="/contacts/$id"
      fx-method="PUT">
    <div class="cell">
        <input name="name"  value="[esc [dict get $c name]]"  autofocus required>
    </div>
    <div class="cell">
        <input name="email" value="[esc [dict get $c email]]" type="email" required>
    </div>
    <div class="cell">
        <input name="phone" value="[esc [dict get $c phone]]" type="tel"   required>
    </div>
    <div class="actions">
        <button live="this.disabled = !this.form.checkValidity()">save</button>
        <button type="button"
                fx-action="/contacts/$id"
                fx-target="#c-$id">
            cancel
        </button>
    </div>
</form>
}]
}

proc viewPage {contacts} {
    set list [viewList $contacts]
    set body [subst {<h1 xmlns:on-fx="http://www.w3.org/1999/xhtml">&#x1F4D2; Contacts</h1>

<div class="contacts">
    <div class="toolbar">
        <input id="search" name="q" type="search" placeholder="Search name, email, phone&hellip;"
               autofocus
               fx-action="/contacts"
               fx-trigger="search"
               fx-target="#contacts-list"
               fx-swap="morph"
               on-input="await debounce(180); trigger('search')">

        <form class="new" fx-action="/contacts"
                          fx-method="POST"
                          fx-target="#contacts-list"
                          fx-swap="morph"
                          on-fx:swapped="this.reset(); q('first input').focus()">
            <input name="name"  placeholder="New name" required>
            <input name="email" placeholder="email"    type="email" required>
            <input name="phone" placeholder="phone"    type="tel"   required>
            <button live="this.disabled = !this.form.checkValidity()">+ Add</button>
        </form>
    </div>

    <div class="row header">
        <div>Name</div>
        <div>Email</div>
        <div>Phone</div>
        <div></div>
    </div>

    $list
</div>
}]
    return [pageShell "Contacts" "contacts" $body]
}

# Full HTML5 document shell, equivalent to demo/views/_layout.eta.
proc pageShell {title page body} {
    return [subst {<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>$title - fixi demo</title>
<script src="/dist/the-fixi-project.js"></script>
<link rel="stylesheet" href="/css/layout.css">
<link rel="stylesheet" href="/css/$page.css">
</head>
<body>
<header class="nav"><a href="/">&larr; demo index</a></header>
$body
</body>
</html>
}]
}
