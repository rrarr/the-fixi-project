# router.tcl -- tiny method+path router, Tcl port of demo/lib/router.mjs.
# Patterns are strings like "/contacts/:id/edit"; each :name segment
# matches one path component and ends up in the params dict passed to
# the handler.

set ROUTES {}

proc splitPath {path} {
    return [lsearch -all -inline -not -exact [split $path "/"] ""]
}

# Register a route: method is "GET"/"POST"/"PUT"/"DELETE", pattern a
# string, handler a proc name taking {chan params query form}.
proc route {method pattern handler} {
    global ROUTES
    lappend ROUTES [list $method [splitPath $pattern] $handler]
}

# Try to match segments against a pattern's segments. Returns a dict of
# params, or returns 0 via the varName "ok" flag.
proc matchPattern {patSegs pathSegs okVar} {
    upvar $okVar ok
    set params [dict create]
    if {[llength $patSegs] != [llength $pathSegs]} {
        set ok 0
        return $params
    }
    foreach p $patSegs s $pathSegs {
        if {[string index $p 0] eq ":"} {
            dict set params [string range $p 1 end] $s
        } elseif {$p ne $s} {
            set ok 0
            return $params
        }
    }
    set ok 1
    return $params
}

# Dispatch (method path) against all registered routes, in registration
# order. Calls the matching handler as {handler chan params query form}
# and returns 1, or 0 if nothing matched.
proc dispatch {method path chan query form} {
    global ROUTES
    set segs [splitPath $path]
    foreach r $ROUTES {
        lassign $r rMethod rPat rHandler
        if {$rMethod ne $method} continue
        set ok 0
        set params [matchPattern $rPat $segs ok]
        if {$ok} {
            $rHandler $chan $params $query $form
            return 1
        }
    }
    return 0
}
