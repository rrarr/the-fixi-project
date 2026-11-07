# contacts.tcl -- in-memory contact store, direct port of
# demo/apps/contacts.mjs. Each contact is a dict with id/name/email/phone.

set CONTACTS {}
lappend CONTACTS [dict create id 1 name "Lena Park"    email "lena@example.com"        phone "555-0101"]
lappend CONTACTS [dict create id 2 name "Kai Bennett"   email "kai@example.com"         phone "555-0102"]
lappend CONTACTS [dict create id 3 name "Yuki Tanaka"   email "yuki.tanaka@example.com" phone "555-0103"]
lappend CONTACTS [dict create id 4 name "Priya Sharma"  email "priya@example.com"       phone "555-0104"]
lappend CONTACTS [dict create id 5 name "Diego Ramos"   email "diego.ramos@example.com" phone "555-0105"]
lappend CONTACTS [dict create id 6 name "Mei Chen"      email "mei@example.com"         phone "555-0106"]
lappend CONTACTS [dict create id 7 name "Olu Adesina"   email "olu@example.com"         phone "555-0107"]

set NEXT_ID 8

proc trimTo {s n} {
    set s [string trim $s]
    return [string range $s 0 [expr {$n-1}]]
}

proc contactsAll {} {
    global CONTACTS
    return $CONTACTS
}

proc contactsFind {id} {
    global CONTACTS
    if {[catch {set id [expr {int($id)}]}]} { return "" }
    foreach c $CONTACTS {
        if {[dict get $c id] == $id} { return $c }
    }
    return ""
}

proc contactsSearch {q} {
    global CONTACTS
    if {$q eq ""} { return $CONTACTS }
    set n [string tolower $q]
    set out {}
    foreach c $CONTACTS {
        if {[string first $n [string tolower [dict get $c name]]] >= 0 ||
            [string first $n [string tolower [dict get $c email]]] >= 0 ||
            [string first $n [dict get $c phone]] >= 0} {
            lappend out $c
        }
    }
    return $out
}

proc contactsAdd {name email phone} {
    global CONTACTS NEXT_ID
    set n [trimTo $name 80]
    if {$n eq ""} { return "" }
    set c [dict create id $NEXT_ID name $n email [trimTo $email 80] phone [trimTo $phone 40]]
    incr NEXT_ID
    lappend CONTACTS $c
    return $c
}

proc contactsUpdate {id name email phone} {
    global CONTACTS
    set idx -1
    if {[catch {set id [expr {int($id)}]}]} { return "" }
    for {set i 0} {$i < [llength $CONTACTS]} {incr i} {
        if {[dict get [lindex $CONTACTS $i] id] == $id} { set idx $i; break }
    }
    if {$idx < 0} { return "" }
    set c [lindex $CONTACTS $idx]
    set n [trimTo $name 80]
    if {$n ne ""} { dict set c name $n }
    dict set c email [trimTo $email 80]
    dict set c phone [trimTo $phone 40]
    set CONTACTS [lreplace $CONTACTS $idx $idx $c]
    return $c
}

proc contactsRemove {id} {
    global CONTACTS
    if {[catch {set id [expr {int($id)}]}]} { return 0 }
    for {set i 0} {$i < [llength $CONTACTS]} {incr i} {
        if {[dict get [lindex $CONTACTS $i] id] == $id} {
            set CONTACTS [lreplace $CONTACTS $i $i]
            return 1
        }
    }
    return 0
}
