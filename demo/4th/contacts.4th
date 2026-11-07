\ contacts.4th -- 4tH port of the Contacts demo (store layer first;
\ HTTP layer is added once this is verified standalone).

include lib/digit.4th
include lib/tonumber.4th
include lib/compare.4th
include lib/scanskip.4th
include lib/files.4th

31 constant FS
file DataFile

: next-part ( a n c -- field-a field-n rest-a rest-n )
  split 2swap
  dup if swap 1+ swap 1- then
;

: ltrim ( a n -- a2 n2 )
  begin dup while over c@ bl = while 1- swap 1+ swap repeat ;
: trim ( a n -- a2 n2 ) ltrim -trailing ;

: str>num ( a n -- n ) 0 -rot >number drop drop ;
: numtype ( n -- ) s>d <# #s #> type ;

: hexdigit ( c -- n )
  dup [char] 0 >= over [char] 9 <= and if [char] 0 - exit then
  dup [char] A >= over [char] F <= and if [char] A - 10 + exit then
  dup [char] a >= over [char] f <= and if [char] a - 10 + exit then
  drop 0
;
: hex2 ( c1 c2 -- byte ) >r hexdigit r> hexdigit swap 16 * + ;

256 buffer: decbuf
0 value declen
0 value hx-a
: decc ( c -- ) decbuf declen + c! declen 1+ to declen ;

\ Decode a application/x-www-form-urlencoded string: '+' -> space,
\ '%XX' -> byte XX, everything else verbatim.
: url-decode ( a n -- a2 n2 )
  0 to declen
  begin dup while
    over c@ [char] + = if
      bl decc 1 /string
    else over c@ [char] % = if
      dup 3 >= if
        over to hx-a
        1 /string
        hx-a 1+ c@ hx-a 2 + c@ hex2 decc
        2 /string
      else
        over c@ decc 1 /string
      then
    else
      over c@ decc 1 /string
    then then
  repeat 2drop decbuf declen
;

\ --- the store: one packed "id FS name FS email FS phone" line per slot --

64 constant MAXC
256 constant /rec
MAXC /rec * buffer: records
: rec-slot ( i -- a ) /rec * records + ;

0 value nc
8 value next-id

256 buffer: recbuf
0 value rlen
: rec-reset 0 to rlen ;
: rec-str ( a n -- ) dup >r recbuf rlen + swap cmove r> rlen + to rlen ;
: rec-chr ( c -- ) recbuf rlen + c! rlen 1+ to rlen ;
: rec-num ( n -- ) s>d <# #s #> rec-str ;

0 value pid
0 value p-na 0 value p-nn
0 value p-ea 0 value p-en
0 value p-pha 0 value p-phn
0 value p-idx

\ Captures args in the order they arrive on the stack (last-pushed =
\ first popped = idx, id, phone, email, name), then writes the record
\ out in the fixed on-disk field order (id, name, email, phone) by
\ referring to the named values instead of stack position.
: put-rec ( name-a name-n email-a email-n phone-a phone-n id idx -- )
  to p-idx to pid to p-phn to p-pha to p-en to p-ea to p-nn to p-na
  rec-reset
  pid rec-num FS rec-chr
  p-na p-nn rec-str FS rec-chr
  p-ea p-en rec-str FS rec-chr
  p-pha p-phn rec-str
  recbuf rlen p-idx rec-slot place
;

0 value la  0 value ln
0 value id1
0 value na  0 value nn
0 value ea  0 value en
0 value pha 0 value phn

: rec-fields ( i -- )
  rec-slot count
  FS next-part to ln to la
  str>num to id1
  la ln FS next-part to ln to la to nn to na
  la ln FS next-part to ln to la to en to ea
  la to pha ln to phn
;

: find-idx ( id -- idx )
  nc 0 ?do i rec-fields id1 over = if drop i unloop exit then loop drop -1 ;

0 value uc-na 0 value uc-nn
0 value uc-ea 0 value uc-en
0 value uc-pa 0 value uc-pn
0 value upd-idx
: update-contact ( id name-a name-n email-a email-n phone-a phone-n -- idx )
  to uc-pn to uc-pa to uc-en to uc-ea to uc-nn to uc-na
  dup find-idx to upd-idx
  upd-idx -1 = if drop upd-idx exit then
  drop
  upd-idx rec-fields
  uc-na uc-nn trim to uc-nn to uc-na
  uc-nn 0= if na nn to uc-nn to uc-na else uc-nn 80 min to uc-nn then
  uc-ea uc-en trim to uc-en to uc-ea uc-en 80 min to uc-en
  uc-pa uc-pn trim to uc-pn to uc-pa uc-pn 40 min to uc-pn
  uc-na uc-nn uc-ea uc-en uc-pa uc-pn id1 upd-idx put-rec
  upd-idx
;

: remove-contact ( id -- flag )
  find-idx dup -1 = if drop false exit then
  >r
  nc r@ 1+ ?do
    i rec-slot count i 1- rec-slot place
  loop
  r> drop
  nc 1- to nc
  true
;

0 value ac-na 0 value ac-nn
0 value ac-ea 0 value ac-en
0 value ac-pa 0 value ac-pn
: add-contact ( name-a name-n email-a email-n phone-a phone-n -- )
  to ac-pn to ac-pa to ac-en to ac-ea to ac-nn to ac-na
  ac-na ac-nn trim to ac-nn to ac-na ac-nn 80 min to ac-nn
  ac-ea ac-en trim to ac-en to ac-ea ac-en 80 min to ac-en
  ac-pa ac-pn trim to ac-pn to ac-pa ac-pn 40 min to ac-pn
  ac-nn 0= if exit then
  nc MAXC >= if exit then
  ac-na ac-nn ac-ea ac-en ac-pa ac-pn next-id nc put-rec
  nc 1+ to nc
  next-id 1+ to next-id
;

: seed-defaults
  0 to nc 1 to next-id
  s" Lena Park" s" lena@example.com" s" 555-0101" add-contact
  s" Kai Bennett" s" kai@example.com" s" 555-0102" add-contact
  s" Yuki Tanaka" s" yuki.tanaka@example.com" s" 555-0103" add-contact
  s" Priya Sharma" s" priya@example.com" s" 555-0104" add-contact
  s" Diego Ramos" s" diego.ramos@example.com" s" 555-0105" add-contact
  s" Mei Chen" s" mei@example.com" s" 555-0106" add-contact
  s" Olu Adesina" s" olu@example.com" s" 555-0107" add-contact
;

0 value lid
: load-line ( a n -- )
  FS next-part to ln to la str>num to lid
  la ln FS next-part to ln to la to nn to na
  la ln FS next-part to ln to la to en to ea
  na nn ea en la ln lid nc put-rec
  nc 1+ to nc
  lid next-id >= if lid 1+ to next-id then
;

: load-store ( a n -- )
  2dup exist? 0= if 2drop seed-defaults exit then
  input open error? abort" cannot open datafile" to DataFile
  DataFile use
  0 to nc 1 to next-id
  begin refill while
    tib count trim
    dup if load-line else 2drop then
  repeat
  stdin use DataFile close
;

: save-store ( a n -- )
  output open error? abort" cannot open datafile for writing" to DataFile
  DataFile use
  nc 0 ?do
    i rec-fields
    id1 numtype FS emit
    na nn type FS emit
    ea en type FS emit
    pha phn type cr
  loop
  stdout use DataFile close
;

\ --- output buffer & HTML escaping ---------------------------------------

32768 buffer: outbuf
0 value outlen
: out-reset 0 to outlen ;
: outapp ( a n -- ) dup >r outbuf outlen + swap cmove r> outlen + to outlen ;
: outc ( c -- ) outbuf outlen + c! outlen 1+ to outlen ;
: outnum ( n -- ) s>d <# #s #> outapp ;
: dq ( -- ) [char] " outc ;

\ Plain if/else chain, not case/of/endof -- that construct turned out to
\ leave a residual stack imbalance once code falls through two or more
\ failed OF comparisons to reach a default branch (confirmed with a
\ minimal standalone repro). if/else is more verbose but verified safe.
: html-esc ( a n -- )
  bounds ?do
    i c@
    dup [char] & = if drop s" &amp;" outapp else
    dup [char] < = if drop s" &lt;" outapp else
    dup [char] > = if drop s" &gt;" outapp else
    dup [char] " = if drop s" &quot;" outapp else
    dup [char] ' = if drop s" &#39;" outapp else
    outc
    then then then then then
  loop
;

: is? ( a n lit-a lit-n -- flag ) compare 0= ;

\ --- views ----------------------------------------------------------

: view-row ( i -- )
  rec-fields
  s" <div class=" outapp dq s" row" outapp dq s"  id=" outapp dq
    s" c-" outapp id1 outnum dq s" >" outapp
  s" <div class=" outapp dq s" cell" outapp dq s" >" outapp na nn html-esc s" </div>" outapp
  s" <div class=" outapp dq s" cell" outapp dq s" >" outapp ea en html-esc s" </div>" outapp
  s" <div class=" outapp dq s" cell" outapp dq s" >" outapp pha phn html-esc s" </div>" outapp
  s" <div class=" outapp dq s" actions" outapp dq s" >" outapp
  s" <button fx-action=" outapp dq s" /contacts/" outapp id1 outnum s" /edit" outapp dq
    s"  fx-target=" outapp dq s" #c-" outapp id1 outnum dq s" >edit</button>" outapp
  s" <button class=" outapp dq s" danger" outapp dq
    s"  fx-action=" outapp dq s" /contacts/" outapp id1 outnum dq
    s"  fx-method=" outapp dq s" DELETE" outapp dq
    s"  fx-target=" outapp dq s" #c-" outapp id1 outnum dq
    s"  on-fx:config=" outapp dq s" cfg.confirm = () =&gt; confirm(&#39;Delete this contact?&#39;)" outapp dq
    s" >&times;</button>" outapp
  s" </div></div>" outapp
;

: view-list ( -- )            \ renders the CURRENTLY LOADED store (nc records)
  s" <div id=" outapp dq s" contacts-list" outapp dq s" >" outapp
  nc 0= if
    s" <div class=" outapp dq s" row empty" outapp dq s" >No matches.</div>" outapp
  else
    nc 0 ?do i view-row loop
  then
  s" </div>" outapp
;

\ Case-sensitive substring search (known simplification -- the other
\ ports lowercase both sides first; skipped here for time).
0 value csa 0 value csn 0 value cpa 0 value cpn
: contains? ( a n pat-a pat-n -- flag )
  to cpn to cpa to csn to csa
  csn cpn - 1+ 0 max 0 ?do
    csa i + cpn cpa cpn compare 0= if true unloop exit then
  loop false
;

MAXC /rec * buffer: sresults
0 value sfcount
: sres-slot ( i -- a ) /rec * sresults + ;

0 value sq-a 0 value sq-n
: search-store ( q-a q-n -- )
  to sq-n to sq-a
  0 to sfcount
  nc 0 ?do
    i rec-fields
    sq-n 0=
    na nn sq-a sq-n contains? or
    ea en sq-a sq-n contains? or
    pha phn sq-a sq-n contains? or
    if
      i rec-slot count sfcount sres-slot place
      sfcount 1+ to sfcount
    then
  loop
;

\ Filters `records`/`nc` in place to just the matches. Safe because this
\ process never persists after a read-only search (save-store is only
\ called from the mutating routes, which don't search first).
: apply-search ( q-a q-n -- )
  search-store
  sfcount 0 ?do i sres-slot count i rec-slot place loop
  sfcount to nc
;

: view-edit ( i -- )
  rec-fields
  s" <form class=" outapp dq s" row editing" outapp dq
    s"  id=" outapp dq s" c-" outapp id1 outnum dq
    s"  fx-action=" outapp dq s" /contacts/" outapp id1 outnum dq
    s"  fx-method=" outapp dq s" PUT" outapp dq s" >" outapp
  s" <div class=" outapp dq s" cell" outapp dq s" ><input name=" outapp dq s" name" outapp dq
    s"  value=" outapp dq na nn html-esc dq s"  autofocus required></div>" outapp
  s" <div class=" outapp dq s" cell" outapp dq s" ><input name=" outapp dq s" email" outapp dq
    s"  value=" outapp dq ea en html-esc dq s"  type=" outapp dq s" email" outapp dq s"  required></div>" outapp
  s" <div class=" outapp dq s" cell" outapp dq s" ><input name=" outapp dq s" phone" outapp dq
    s"  value=" outapp dq pha phn html-esc dq s"  type=" outapp dq s" tel" outapp dq s"  required></div>" outapp
  s" <div class=" outapp dq s" actions" outapp dq s" >" outapp
  s" <button live=" outapp dq s" this.disabled = !this.form.checkValidity()" outapp dq s" >save</button>" outapp
  s" <button type=" outapp dq s" button" outapp dq
    s"  fx-action=" outapp dq s" /contacts/" outapp id1 outnum dq
    s"  fx-target=" outapp dq s" #c-" outapp id1 outnum dq s" >cancel</button>" outapp
  s" </div></form>" outapp
;

: view-page ( -- )
  s" <!DOCTYPE html><html lang=" outapp dq s" en" outapp dq s" ><head><meta charset=" outapp dq s" UTF-8" outapp dq s" >" outapp
  s" <title>Contacts - fixi demo</title>" outapp
  s" <script src=" outapp dq s" /dist/the-fixi-project.js" outapp dq s" ></script>" outapp
  s" <link rel=" outapp dq s" stylesheet" outapp dq s"  href=" outapp dq s" /css/layout.css" outapp dq s" >" outapp
  s" <link rel=" outapp dq s" stylesheet" outapp dq s"  href=" outapp dq s" /css/contacts.css" outapp dq s" >" outapp
  s" </head><body><header class=" outapp dq s" nav" outapp dq s" ><a href=" outapp dq s" /" outapp dq s" >&larr; demo index</a></header>" outapp
  s" <h1>&#x1F4D2; Contacts</h1>" outapp
  s" <div class=" outapp dq s" contacts" outapp dq s" ><div class=" outapp dq s" toolbar" outapp dq s" >" outapp
  s" <input id=" outapp dq s" search" outapp dq s"  name=" outapp dq s" q" outapp dq s"  type=" outapp dq s" search" outapp dq
    s"  placeholder=" outapp dq s" Search name, email, phone&hellip;" outapp dq
    s"  autofocus fx-action=" outapp dq s" /contacts" outapp dq
    s"  fx-trigger=" outapp dq s" search" outapp dq
    s"  fx-target=" outapp dq s" #contacts-list" outapp dq
    s"  fx-swap=" outapp dq s" morph" outapp dq
    s"  on-input=" outapp dq s" await debounce(180); trigger('search')" outapp dq s" >" outapp
  s" <form class=" outapp dq s" new" outapp dq
    s"  fx-action=" outapp dq s" /contacts" outapp dq
    s"  fx-method=" outapp dq s" POST" outapp dq
    s"  fx-target=" outapp dq s" #contacts-list" outapp dq
    s"  fx-swap=" outapp dq s" morph" outapp dq
    s"  on-fx:swapped=" outapp dq s" this.reset(); q('first input').focus()" outapp dq s" >" outapp
  s" <input name=" outapp dq s" name" outapp dq s"  placeholder=" outapp dq s" New name" outapp dq s"  required>" outapp
  s" <input name=" outapp dq s" email" outapp dq s"  placeholder=" outapp dq s" email" outapp dq s"  type=" outapp dq s" email" outapp dq s"  required>" outapp
  s" <input name=" outapp dq s" phone" outapp dq s"  placeholder=" outapp dq s" phone" outapp dq s"  type=" outapp dq s" tel" outapp dq s"  required>" outapp
  s" <button live=" outapp dq s" this.disabled = !this.form.checkValidity()" outapp dq s" >+ Add</button></form></div>" outapp
  s" <div class=" outapp dq s" row header" outapp dq s" ><div>Name</div><div>Email</div><div>Phone</div><div></div></div>" outapp
  view-list
  s" </div></body></html>" outapp
;

\ --- HTTP response helpers -------------------------------------------

: send-200 ( -- )
  ." HTTP/1.1 200 OK" cr
  ." Content-Type: text/html; charset=utf-8" cr
  ." Content-Length: " outlen numtype cr
  ." Connection: close" cr cr
  outbuf outlen type
;
: send-204 ( -- ) ." HTTP/1.1 204 No Content" cr ." Connection: close" cr cr ;
: send-404 ( -- )
  ." HTTP/1.1 404 Not Found" cr
  ." Content-Type: text/plain" cr
  ." Content-Length: 9" cr
  ." Connection: close" cr cr
  ." not found"
;

\ --- static file serving (mirrors web4th's transfer-file loop) ------

8192 constant /xferbuf
/xferbuf buffer: xferbuf
file StaticFile

: mime-for ( a n -- a2 n2 )
  2dup s" .css" is? if 2drop s" text/css" exit then
  2dup s" .js" is? if 2drop s" text/javascript" exit then
  2dup s" .html" is? if 2drop s" text/html; charset=utf-8" exit then
  2dup s" .json" is? if 2drop s" application/json" exit then
  2drop s" application/octet-stream"
;
\ Scans backward for the LAST '.' (not scanskip's forward `scan`, which
\ would hit the dots in a "../public/..." path prefix before ever
\ reaching the actual file extension's dot).
0 value fea 0 value fen
: file-ext ( a n -- a2 n2 )
  to fen to fea
  fen 0 ?do
    fea fen 1- i - + c@ [char] . = if
      fea fen 1- i - + i 1+ unloop exit
    then
  loop
  fea fen
;

0 value sfa 0 value sfn
: serve-file ( path-a path-n -- )
  to sfn to sfa
  sfa sfn exist? 0= if send-404 exit then
  sfa sfn size >r
  sfa sfn input open error? abort" cannot open static file" to StaticFile
  StaticFile use
  ." HTTP/1.1 200 OK" cr
  ." Content-Type: " sfa sfn file-ext mime-for type cr
  ." Content-Length: " r> numtype cr
  ." Connection: close" cr cr
  begin
    xferbuf /xferbuf accept dup
  while
    xferbuf over type
  repeat drop
  stdin use StaticFile close
;

\ --- request parsing --------------------------------------------------

0 value meth-a  0 value meth-n
0 value path-a  0 value path-n
0 value query-a 0 value query-n
0 value ctlen
0 value ct-a    0 value ct-n
0 value la2     0 value ln2

\ All of these point into TIB, which gets overwritten by the next
\ `refill` -- and read-headers calls refill repeatedly right after this,
\ so method/path/query must be copied out into stable buffers
\ immediately, not left as raw TIB pointers.
96 buffer: methbuf
256 buffer: reqpathbuf
256 buffer: reqquerybuf

: read-request-line ( -- )
  refill drop
  bl parse-word methbuf place
  methbuf count to meth-n to meth-a
  bl parse-word [char] ? next-part to ln2 to la2 to path-n to path-a
  path-a path-n reqpathbuf place
  la2 ln2 reqquerybuf place
  reqpathbuf count to path-n to path-a
  reqquerybuf count to query-n to query-a
;

0 value hdra 0 value hdrn 0 value pfxa 0 value pfxn
\ If (a n) begins with literal (pfx-a pfx-n), returns what follows the
\ prefix plus a true flag; else 0 0 false. Pure scratch-value capture,
\ no return-stack juggling across if/then branches.
: header-value ( a n pfx-a pfx-n -- val-a val-n flag )
  to pfxn to pfxa to hdrn to hdra
  hdrn pfxn < if 0 0 false exit then
  hdra pfxn pfxa pfxn compare 0= if
    hdra pfxn + hdrn pfxn - true
  else
    0 0 false
  then
;

: read-headers ( -- )
  0 to ctlen  0 to ct-n
  begin refill while
    tib count trim
    dup 0= if 2drop exit then
    2dup s" Content-Length: " header-value if
      str>num to ctlen 2drop
    else
      2drop
      2dup s" Content-Type: " header-value if
        to ct-n to ct-a 2drop
      else
        2drop 2drop
      then
    then
  repeat
;

\ --- request body & form parsing -------------------------------------

8192 buffer: bodybuf
0 value body-need 0 value body-got
: read-body ( -- )
  ctlen to body-need
  0 to body-got
  begin body-got body-need < while
    bodybuf body-got +
    body-need body-got - 4096 min
    accept
    dup 0= if drop exit then
    body-got + to body-got
  repeat
;

81 buffer: fnamebuf
81 buffer: femailbuf
41 buffer: fphonebuf
: reset-form
  0 fnamebuf c!  0 femailbuf c!  0 fphonebuf c!
;

0 value kv-a 0 value kv-n
0 value vv-a 0 value vv-n
: parse-form ( a n -- )
  reset-form
  begin dup while
    [char] & next-part to ln2 to la2
    [char] = next-part to vv-n to vv-a to kv-n to kv-a
    kv-a kv-n url-decode
    2dup s" name" is? if
      vv-a vv-n url-decode fnamebuf place
    else 2dup s" email" is? if
      vv-a vv-n url-decode femailbuf place
    else 2dup s" phone" is? if
      vv-a vv-n url-decode fphonebuf place
    then then then
    2drop
    la2 ln2
  repeat
  2drop
;

\ --- path splitting ----------------------------------------------------

0 value s1a 0 value s1n
0 value s2a 0 value s2n
0 value s3a 0 value s3n

: split-path ( a n -- )
  dup if over c@ [char] / = if 1 /string then then
  [char] / next-part to ln2 to la2 to s1n to s1a
  la2 ln2 [char] / next-part to ln2 to la2 to s2n to s2a
  la2 to s3a ln2 to s3n
;

\ --- routing -----------------------------------------------------------

: get-id ( -- id ) s2a s2n str>num ;

81 buffer: qvalbuf
: parse-query ( a n -- )
  0 qvalbuf c!
  begin dup while
    [char] & next-part to ln2 to la2
    [char] = next-part to vv-n to vv-a to kv-n to kv-a
    kv-a kv-n url-decode s" q" is? if
      vv-a vv-n url-decode qvalbuf place
    then
    la2 ln2
  repeat 2drop
;

: do-page out-reset view-page send-200 ;

: do-list
  query-a query-n parse-query
  qvalbuf count apply-search
  out-reset view-list send-200
;

: do-row
  get-id find-idx dup -1 = if drop send-404 exit then
  out-reset view-row send-200
;

: do-edit
  get-id find-idx dup -1 = if drop send-404 exit then
  out-reset view-edit send-200
;

: do-add
  read-body bodybuf body-got parse-form
  fnamebuf count femailbuf count fphonebuf count add-contact
  out-reset view-list send-200
;

: do-update
  read-body bodybuf body-got parse-form
  get-id fnamebuf count femailbuf count fphonebuf count update-contact
  dup -1 = if drop send-404 exit then
  out-reset view-row send-200
;

: do-delete
  get-id remove-contact
  if send-204 else send-404 then
;

256 buffer: pathbuf
0 value plen
: preset-path 0 to plen ;
: pstr ( a n -- ) dup >r pathbuf plen + swap cmove r> plen + to plen ;

: serve-static
  preset-path
  s1n 0= if
    s" ../public/index.html" pstr
  else s1a s1n s" css" is? if
    s" ../public/css/" pstr s2a s2n pstr
  else s1a s1n s" dist" is? if
    s" ../../dist/" pstr s2a s2n pstr
  else
    s" ../public/" pstr s1a s1n pstr
  then then then
  pathbuf plen serve-file
;

: route ( -- )
  meth-a meth-n s" GET" is? if
    s1a s1n s" contacts.html" is? if do-page exit then
    s1a s1n s" contacts" is? if
      s2n 0= if do-list exit then
      s3n 0= if do-row exit then
      s3a s3n s" edit" is? if do-edit exit then
      send-404 exit
    then
    serve-static exit
  then
  meth-a meth-n s" POST" is? if
    s1a s1n s" contacts" is? if do-add else send-404 then exit
  then
  meth-a meth-n s" PUT" is? if
    s1a s1n s" contacts" is? if do-update else send-404 then exit
  then
  meth-a meth-n s" DELETE" is? if
    s1a s1n s" contacts" is? if do-delete else send-404 then exit
  then
  send-404
;

: mutating? ( -- flag )
  meth-a meth-n s" POST" is? if true exit then
  meth-a meth-n s" PUT" is? if true exit then
  meth-a meth-n s" DELETE" is? if true exit then
  false
;

0 value is-mutating
0 value data-path-a 0 value data-path-n
\ `1 args` points into a volatile buffer that later word calls (view
\ rendering especially) overwrite -- same class of bug as the TIB
\ pointer issue above. Copy it out immediately.
256 buffer: datapathbuf

: main
  argn 2 < abort" Usage: 4th cxq contacts.4th data-file"
  1 args datapathbuf place
  datapathbuf count to data-path-n to data-path-a
  data-path-a data-path-n load-store
  read-request-line
  read-headers
  path-a path-n split-path
  mutating? to is-mutating
  route
  is-mutating if data-path-a data-path-n save-store then
;

main
