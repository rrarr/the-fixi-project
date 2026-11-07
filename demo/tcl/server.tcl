#!/usr/bin/env tclsh
# server.tcl -- Tcl port of demo/server.mjs for the Contacts demo.
# A stateless HTTP server using Tcl's event-driven socket server: each
# connection is parsed, dispatched by (method path) to a handler, and
# answered with a plain HTML response -- no sessions, all interactivity
# is delegated to fixi on the client.
#
# Run:  tclsh demo/tcl/server.tcl [port]   (or: ./run.sh [port])

set SELF_DIR [file dirname [file normalize [info script]]]
source [file join $SELF_DIR util.tcl]
source [file join $SELF_DIR router.tcl]
source [file join $SELF_DIR views.tcl]

set ROOT [file normalize [file join $SELF_DIR .. ..]]

# --- routes --------------------------------------------------------------

proc h_contactsPage {chan params query form} {
    sendHtml $chan [viewPage [contactsAll]]
}

proc h_contactsList {chan params query form} {
    sendHtml $chan [viewList [contactsSearch [formParam $query q]]]
}

proc h_contactsAdd {chan params query form} {
    contactsAdd [formParam $form name] [formParam $form email] [formParam $form phone]
    sendHtml $chan [viewList [contactsAll]]
}

proc h_contactRow {chan params query form} {
    set c [contactsFind [dict get $params id]]
    if {$c eq ""} { sendNotFound $chan } else { sendHtml $chan [viewRow $c] }
}

proc h_contactEdit {chan params query form} {
    set c [contactsFind [dict get $params id]]
    if {$c eq ""} { sendNotFound $chan } else { sendHtml $chan [viewEdit $c] }
}

proc h_contactUpdate {chan params query form} {
    set c [contactsUpdate [dict get $params id] \
        [formParam $form name] [formParam $form email] [formParam $form phone]]
    if {$c eq ""} { sendNotFound $chan } else { sendHtml $chan [viewRow $c] }
}

proc h_contactDelete {chan params query form} {
    contactsRemove [dict get $params id]
    sendNoContent $chan
}

route GET    /contacts.html      h_contactsPage
route GET    /contacts           h_contactsList
route POST   /contacts           h_contactsAdd
route GET    /contacts/:id       h_contactRow
route GET    /contacts/:id/edit  h_contactEdit
route PUT    /contacts/:id       h_contactUpdate
route DELETE /contacts/:id       h_contactDelete

# --- static assets (css, the fixi client script) -------------------------

proc serveStatic {chan path} {
    global ROOT
    if {[string match {/dist/*} $path]} {
        sendFile $chan [file join $ROOT [string trimleft $path /]]
    } elseif {$path eq "/"} {
        sendFile $chan [file join $ROOT demo public index.html]
    } else {
        sendFile $chan [file join $ROOT demo public [string trimleft $path /]]
    }
}

# --- request handling ------------------------------------------------------
#
# Fully event-driven: nothing here ever calls a blocking `read`/`gets` on
# the socket. Each connection's channel is nonblocking end to end; an
# fileevent readable callback accumulates raw bytes into CONN($chan) and
# re-parses as far as it can get on every wakeup, so one slow/trickling
# client can never stall the reading of any other connection. Writing the
# response relies on Tcl's own nonblocking-channel behavior: `close` on a
# nonblocking channel with buffered output performs a "background close",
# flushing asynchronously without blocking the event loop.

array set CONN {}

proc onAccept {chan addr port} {
    fconfigure $chan -translation binary -blocking 0 -buffering none
    set ::CONN($chan) [dict create phase headers raw ""]
    fileevent $chan readable [list onReadable $chan]
}

proc closeConn {chan} {
    catch { fileevent $chan readable {} }
    catch { fileevent $chan writable {} }
    catch { close $chan }
    unset -nocomplain ::CONN($chan)
}

proc onReadable {chan} {
    if {![info exists ::CONN($chan)]} { catch { close $chan }; return }
    set chunk ""
    if {[catch { set chunk [read $chan 65536] }]} {
        closeConn $chan
        return
    }
    if {$chunk ne ""} {
        set st $::CONN($chan)
        dict set st raw "[dict get $st raw]$chunk"
        set ::CONN($chan) $st
    }
    if {[eof $chan]} {
        closeConn $chan
        return
    }
    if {$chunk eq ""} { return }
    advance $chan
}

# Parse a request line + header block into {method path query headers}.
proc parseHeaderBlock {headerText} {
    set lines [splitLiteral $headerText "\r\n"]
    lassign [split [lindex $lines 0] " "] method full _httpver
    set headers [dict create]
    foreach line [lrange $lines 1 end] {
        if {$line eq ""} continue
        set colon [string first ":" $line]
        if {$colon < 0} continue
        set name [string tolower [string trim [string range $line 0 [expr {$colon-1}]]]]
        set value [string trim [string range $line [expr {$colon+1}] end]]
        dict set headers $name $value
    }
    return [list $method $full $headers]
}

proc parseBody {bodyBytes headers} {
    set ctype ""
    if {[dict exists $headers content-type]} { set ctype [dict get $headers content-type] }
    if {[string match -nocase "*multipart/form-data*" $ctype]} {
        return [parseMultipart $bodyBytes [mpBoundary $ctype]]
    } elseif {[string match -nocase "*application/json*" $ctype]} {
        # Minimal JSON object parser for flat {"k":"v",...} bodies.
        set form [dict create]
        foreach {_ k v} [regexp -all -inline {"([^"]+)"\s*:\s*"((?:[^"\\]|\\.)*)"} $bodyBytes] {
            dict set form $k $v
        }
        return $form
    }
    return [parseForm $bodyBytes]
}

# Advance CONN($chan) as far as the bytes accumulated so far allow: from
# "headers" (waiting on a full "\r\n\r\n" block) to "body" (waiting on
# Content-Length bytes) to dispatching the finished request. Returns
# without doing anything once it needs more data than has arrived yet.
proc advance {chan} {
    set st $::CONN($chan)
    set phase [dict get $st phase]

    if {$phase eq "headers"} {
        set raw [dict get $st raw]
        set idx [string first "\r\n\r\n" $raw]
        if {$idx < 0} { return }
        set headerText [string range $raw 0 [expr {$idx-1}]]
        set rest [string range $raw [expr {$idx+4}] end]
        lassign [parseHeaderBlock $headerText] method full headers

        set qpos [string first "?" $full]
        if {$qpos >= 0} {
            set path [string range $full 0 [expr {$qpos-1}]]
            set queryStr [string range $full [expr {$qpos+1}] end]
        } else {
            set path $full
            set queryStr ""
        }

        set len 0
        if {[dict exists $headers content-length]} { set len [dict get $headers content-length] }

        dict set st phase body
        dict set st method $method
        dict set st path $path
        dict set st query [parseForm $queryStr]
        dict set st headers $headers
        dict set st bodyLen $len
        dict set st raw $rest
        set ::CONN($chan) $st
        advance $chan
        return
    }

    if {$phase eq "body"} {
        set raw [dict get $st raw]
        set len [dict get $st bodyLen]
        if {[string length $raw] < $len} { return }

        set bodyBytes [string range $raw 0 [expr {$len-1}]]
        set form [parseBody $bodyBytes [dict get $st headers]]
        set method [dict get $st method]
        set path [dict get $st path]
        set query [dict get $st query]

        fileevent $chan readable {}
        if {![dispatch $method $path $chan $query $form]} {
            if {$method eq "GET"} {
                serveStatic $chan $path
            } else {
                sendNotFound $chan
            }
        }
        closeConn $chan
        return
    }
}

proc main {} {
    set port 8767
    if {$::argc > 0} { set port [lindex $::argv 0] }
    socket -server onAccept $port
    puts "Contacts demo (Tcl) listening on http://localhost:$port/contacts.html"
    vwait forever
}

main
