\ views.fs -- HTML generation, streaming directly to the client socket
\ (no output buffer/Content-Length -- same "Connection: close" framing
\ demo/4th/web4th-style ports use; curl/ab read until the socket closes).

: ws ( c-addr u sock -- ) write-socket ;
: wsl ( c-addr u sock -- ) { sock } 2dup sock ws s\" \r\n" sock ws ;

1 buffer: chbuf
: wc ( c sock -- ) { sock } chbuf c! chbuf 1 sock ws ;
: dq ( sock -- ) [char] " swap wc ;

: esc-char ( c sock -- )
  { sock }
  dup [char] & = if drop s" &amp;" sock ws exit then
  dup [char] < = if drop s" &lt;" sock ws exit then
  dup [char] > = if drop s" &gt;" sock ws exit then
  dup [char] " = if drop s" &quot;" sock ws exit then
  dup [char] ' = if drop s" &#39;" sock ws exit then
  sock wc
;
: html-esc ( a n sock -- )
  { sock }
  bounds ?do i c@ sock esc-char loop
;

\ --- single-connection-at-a-time convention: a global "current socket"
\ keeps every view word from having to thread `sock` through every call

0 Value cursock
: w ( c-addr u -- ) cursock ws ;
: wq ( -- ) cursock dq ;
: wn ( n -- ) num>str w ;
: we ( a n -- ) cursock html-esc ;

: view-row-body ( -- )  \ assumes rec-fields/fields-of already ran
  s" <div class=" w wq s" row" w wq s"  id=" w wq s" c-" w id1 wn wq s" >" w
  s" <div class=" w wq s" cell" w wq s" >" w na nn we s" </div>" w
  s" <div class=" w wq s" cell" w wq s" >" w ea en we s" </div>" w
  s" <div class=" w wq s" cell" w wq s" >" w pha phn we s" </div>" w
  s" <div class=" w wq s" actions" w wq s" >" w
  s" <button fx-action=" w wq s" /contacts/" w id1 wn s" /edit" w wq
    s"  fx-target=" w wq s" #c-" w id1 wn wq s" >edit</button>" w
  s" <button class=" w wq s" danger" w wq
    s"  fx-action=" w wq s" /contacts/" w id1 wn wq
    s"  fx-method=" w wq s" DELETE" w wq
    s"  fx-target=" w wq s" #c-" w id1 wn wq
    s"  on-fx:config=" w wq s" cfg.confirm = () =&gt; confirm(&#39;Delete this contact?&#39;)" w wq
    s" >&times;</button>" w
  s" </div></div>" w
;

: view-row ( i -- ) rec-fields view-row-body ;
\ For search results: read straight from sresults/sfcount (a separate
\ scratch buffer), never from the live records/nc -- a search must
\ never mutate the persistent store. See the NOTE in contacts.fs.
: view-search-row ( i -- ) sres-slot fields-of view-row-body ;

: view-list ( -- )
  s" <div id=" w wq s" contacts-list" w wq s" >" w
  nc 0= if
    s" <div class=" w wq s" row empty" w wq s" >No matches.</div>" w
  else
    nc 0 ?do i view-row loop
  then
  s" </div>" w
;

: view-search-list ( -- )
  s" <div id=" w wq s" contacts-list" w wq s" >" w
  sfcount 0= if
    s" <div class=" w wq s" row empty" w wq s" >No matches.</div>" w
  else
    sfcount 0 ?do i view-search-row loop
  then
  s" </div>" w
;

: view-edit ( i -- )
  rec-fields
  s" <form class=" w wq s" row editing" w wq
    s"  id=" w wq s" c-" w id1 wn wq
    s"  fx-action=" w wq s" /contacts/" w id1 wn wq
    s"  fx-method=" w wq s" PUT" w wq s" >" w
  s" <div class=" w wq s" cell" w wq s" ><input name=" w wq s" name" w wq
    s"  value=" w wq na nn we wq s"  autofocus required></div>" w
  s" <div class=" w wq s" cell" w wq s" ><input name=" w wq s" email" w wq
    s"  value=" w wq ea en we wq s"  type=" w wq s" email" w wq s"  required></div>" w
  s" <div class=" w wq s" cell" w wq s" ><input name=" w wq s" phone" w wq
    s"  value=" w wq pha phn we wq s"  type=" w wq s" tel" w wq s"  required></div>" w
  s" <div class=" w wq s" actions" w wq s" >" w
  s" <button live=" w wq s" this.disabled = !this.form.checkValidity()" w wq s" >save</button>" w
  s" <button type=" w wq s" button" w wq
    s"  fx-action=" w wq s" /contacts/" w id1 wn wq
    s"  fx-target=" w wq s" #c-" w id1 wn wq s" >cancel</button>" w
  s" </div></form>" w
;

: view-page ( -- )
  s" <!DOCTYPE html><html lang=" w wq s" en" w wq s" ><head><meta charset=" w wq s" UTF-8" w wq s" >" w
  s" <title>Contacts - fixi demo</title>" w
  s" <script src=" w wq s" /dist/the-fixi-project.js" w wq s" ></script>" w
  s" <link rel=" w wq s" stylesheet" w wq s"  href=" w wq s" /css/layout.css" w wq s" >" w
  s" <link rel=" w wq s" stylesheet" w wq s"  href=" w wq s" /css/contacts.css" w wq s" >" w
  s" </head><body><header class=" w wq s" nav" w wq s" ><a href=" w wq s" /" w wq s" >&larr; demo index</a></header>" w
  s" <h1>&#x1F4D2; Contacts</h1>" w
  s" <div class=" w wq s" contacts" w wq s" ><div class=" w wq s" toolbar" w wq s" >" w
  s" <input id=" w wq s" search" w wq s"  name=" w wq s" q" w wq s"  type=" w wq s" search" w wq
    s"  placeholder=" w wq s" Search name, email, phone&hellip;" w wq
    s"  autofocus fx-action=" w wq s" /contacts" w wq
    s"  fx-trigger=" w wq s" search" w wq
    s"  fx-target=" w wq s" #contacts-list" w wq
    s"  fx-swap=" w wq s" morph" w wq
    s"  on-input=" w wq s" await debounce(180); trigger('search')" w wq s" >" w
  s" <form class=" w wq s" new" w wq
    s"  fx-action=" w wq s" /contacts" w wq
    s"  fx-method=" w wq s" POST" w wq
    s"  fx-target=" w wq s" #contacts-list" w wq
    s"  fx-swap=" w wq s" morph" w wq
    s"  on-fx:swapped=" w wq s" this.reset(); q('first input').focus()" w wq s" >" w
  s" <input name=" w wq s" name" w wq s"  placeholder=" w wq s" New name" w wq s"  required>" w
  s" <input name=" w wq s" email" w wq s"  placeholder=" w wq s" email" w wq s"  type=" w wq s" email" w wq s"  required>" w
  s" <input name=" w wq s" phone" w wq s"  placeholder=" w wq s" phone" w wq s"  type=" w wq s" tel" w wq s"  required>" w
  s" <button live=" w wq s" this.disabled = !this.form.checkValidity()" w wq s" >+ Add</button></form></div>" w
  s" <div class=" w wq s" row header" w wq s" ><div>Name</div><div>Email</div><div>Phone</div><div></div></div>" w
  view-list
  s" </div></body></html>" w
;
