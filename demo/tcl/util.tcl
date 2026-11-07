# util.tcl -- request parsing and response helpers, Tcl port of
# demo/lib/util.mjs.

proc esc {s} {
    string map {& &amp; < &lt; > &gt; \" &quot; ' &#39;} $s
}

proc urlDecode {s} {
    set s [string map {+ " "} $s]
    set out ""
    set i 0
    set n [string length $s]
    while {$i < $n} {
        set c [string index $s $i]
        if {$c eq "%" && $i + 2 < $n} {
            set hex [string range $s [expr {$i+1}] [expr {$i+2}]]
            append out [format %c 0x$hex]
            incr i 3
        } else {
            append out $c
            incr i
        }
    }
    return $out
}

# Parse a "a=b&c=d" query/body string into a dict.
proc parseForm {s} {
    set d [dict create]
    if {$s eq ""} { return $d }
    foreach pair [split $s "&"] {
        if {$pair eq ""} continue
        set eq [string first "=" $pair]
        if {$eq < 0} {
            dict set d [urlDecode $pair] ""
        } else {
            set k [urlDecode [string range $pair 0 [expr {$eq-1}]]]
            set v [urlDecode [string range $pair [expr {$eq+1}] end]]
            dict set d $k $v
        }
    }
    return $d
}

# Extract the boundary token from a "multipart/form-data; boundary=XXX"
# Content-Type header value, stripping surrounding quotes if present.
proc mpBoundary {contentType} {
    if {![regexp {boundary=("?)([^;"]+)\1} $contentType -> _ b]} {
        return ""
    }
    return $b
}

# Split s on literal occurrences of needle (unlike Tcl's builtin `split`,
# which treats its second argument as a set of characters).
proc splitLiteral {s needle} {
    set out {}
    set nlen [string length $needle]
    while {1} {
        set i [string first $needle $s]
        if {$i < 0} { lappend out $s; break }
        lappend out [string range $s 0 [expr {$i-1}]]
        set s [string range $s [expr {$i+$nlen}] end]
    }
    return $out
}

# Minimal multipart/form-data parser for text fields.
proc parseMultipart {body boundary} {
    set d [dict create]
    set marker "--$boundary"
    foreach part [splitLiteral $body $marker] {
        set hdrEnd [string first "\r\n\r\n" $part]
        if {$hdrEnd < 0} continue
        set headers [string range $part 0 [expr {$hdrEnd-1}]]
        set content [string range $part [expr {$hdrEnd+4}] end]
        set content [regsub {\r\n$} $content ""]
        if {[regexp {name="([^"]+)"} $headers -> name]} {
            dict set d $name $content
        }
    }
    return $d
}

proc formParam {d key} {
    if {[dict exists $d $key]} { return [dict get $d $key] }
    return ""
}

set MIME [dict create \
    html "text/html; charset=utf-8" \
    js   "text/javascript; charset=utf-8" \
    css  "text/css; charset=utf-8" \
    json "application/json; charset=utf-8" \
    map  "application/json; charset=utf-8" \
]

proc mimeFor {path} {
    global MIME
    set ext [string trimleft [file extension $path] "."]
    if {[dict exists $MIME $ext]} { return [dict get $MIME $ext] }
    return "application/octet-stream"
}

proc statusText {n} {
    switch -- $n {
        200 { return "200 OK" }
        204 { return "204 No Content" }
        404 { return "404 Not Found" }
        405 { return "405 Method Not Allowed" }
        default { return "$n ?" }
    }
}

proc sendHtml {chan html} {
    fconfigure $chan -translation binary -blocking 0
    set len [string length $html]
    puts -nonewline $chan "HTTP/1.1 [statusText 200]\r\n"
    puts -nonewline $chan "Content-Type: text/html; charset=utf-8\r\n"
    puts -nonewline $chan "Content-Length: $len\r\n"
    puts -nonewline $chan "Connection: close\r\n\r\n"
    puts -nonewline $chan $html
}

proc sendNoContent {chan} {
    fconfigure $chan -translation binary -blocking 0
    puts -nonewline $chan "HTTP/1.1 [statusText 204]\r\n"
    puts -nonewline $chan "Connection: close\r\n\r\n"
}

proc sendNotFound {chan} {
    fconfigure $chan -translation binary -blocking 0
    set body "not found"
    puts -nonewline $chan "HTTP/1.1 [statusText 404]\r\n"
    puts -nonewline $chan "Content-Type: text/plain\r\n"
    puts -nonewline $chan "Content-Length: [string length $body]\r\n"
    puts -nonewline $chan "Connection: close\r\n\r\n"
    puts -nonewline $chan $body
}

proc sendFile {chan path} {
    if {![file exists $path] || [file isdirectory $path]} {
        sendNotFound $chan
        return
    }
    set f [open $path rb]
    set data [read $f]
    close $f
    fconfigure $chan -translation binary -blocking 0
    puts -nonewline $chan "HTTP/1.1 [statusText 200]\r\n"
    puts -nonewline $chan "Content-Type: [mimeFor $path]\r\n"
    puts -nonewline $chan "Content-Length: [string length $data]\r\n"
    puts -nonewline $chan "Connection: close\r\n\r\n"
    puts -nonewline $chan $data
}
