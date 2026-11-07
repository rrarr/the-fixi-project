\ server.fs -- Gforth port of the Contacts demo. A real standalone TCP
\ server (Gforth has an actual socket library, unlike 4tH), one
\ sequential accept loop, in-memory store shared across requests.

require unix/socket.fs
include contacts.fs
include views.fs
include util.fs

1 buffer: spbuf  bl spbuf c!
: sp$ ( -- a n ) spbuf 1 ;
1 buffer: qmbuf  char ? qmbuf c!
: qm$ ( -- a n ) qmbuf 1 ;

\ --- request line/header buffers ---------------------------------------
\ Every one of these is a dedicated, stable buffer: `reqline` gets
\ reused by every subsequent read-line call, so a pointer into it goes
\ stale the moment the next line is read -- same class of bug the Zig
\ and 4tH ports hit with their own reused-buffer pointers. Copy out
\ immediately with `place`.

256 buffer: reqline
96  buffer: methbuf
256 buffer: pathbuf
256 buffer: querybuf

0 Value meth-a   0 Value meth-n
0 Value path-a   0 Value path-n
0 Value query-a  0 Value query-n
0 Value ctlen

: read-req-line ( sock -- )
  reqline 256 rot read-line throw drop { n }
  reqline n sp$ split2 { resta restn }   \ before=method, after captured
  { ma mn }
  ma mn methbuf place methbuf count to meth-n to meth-a

  resta restn sp$ split2 { r2a r2n }      \ before=path+query, after(=HTTP/1.1) discarded
  { pa pn }
  pa pn qm$ split2 { qa qn }              \ after=query (or empty), captured
  { pxa pxn }                             \ before=path-only, capture now (don't reuse stale pa/pn!)
  qa qn querybuf place querybuf count to query-n to query-a
  pxa pxn pathbuf place pathbuf count to path-n to path-a
;

\ --- headers -------------------------------------------------------------

96 buffer: ctbuf
0 Value ct-a 0 Value ct-n

: header-value ( a n pfx-a pfx-n -- val-a val-n flag )
  { a n pa pn }
  n pn < if 0 0 false exit then
  a pn pa pn compare 0= if
    a pn + n pn - true
  else
    0 0 false
  then
;

: read-headers ( sock -- )
  { sock }
  0 to ctlen  0 to ct-n
  begin
    reqline 256 sock read-line throw drop { hn }
    hn 0>
  while
    reqline hn s" Content-Length: " header-value
    if
      str>num to ctlen
    else
      2drop
      reqline hn s" Content-Type: " header-value
      if
        ctbuf place ctbuf count to ct-n to ct-a
      else
        2drop
      then
    then
  repeat
;

\ --- request body ---------------------------------------------------------

8192 buffer: bodybuf

: read-body ( sock -- )
  { sock }
  0 { got }
  begin got ctlen < while
    bodybuf got + ctlen got - sock read-file throw
    dup 0= if drop got to ctlen leave then
    +to got
  repeat
;

\ --- form parsing (application/x-www-form-urlencoded only) --------------

96 buffer: fnamebuf
96 buffer: femailbuf
64 buffer: fphonebuf

: reset-form ( -- )
  0 fnamebuf c!  0 femailbuf c!  0 fphonebuf c!
;

1 buffer: ampbuf  char & ampbuf c!
: amp$ ( -- a n ) ampbuf 1 ;
1 buffer: eqbuf   char = eqbuf c!
: eq$ ( -- a n ) eqbuf 1 ;

: parse-form ( a n -- )
  reset-form
  begin dup 0> while
    amp$ split2 { aa an }           \ before=pair, after(rest of body) captured
    { pa pn }
    pa pn eq$ split2 { va vn }      \ before=key, after=value
    { ka kn }
    ka kn url-decode { da dn }
    da dn s" name" compare 0= if
      va vn url-decode fnamebuf place
    else da dn s" email" compare 0= if
      va vn url-decode femailbuf place
    else da dn s" phone" compare 0= if
      va vn url-decode fphonebuf place
    then then then
    aa an
  repeat
  2drop
;

\ --- HTTP response helpers -------------------------------------------

: send-200 ( -- )
  s" HTTP/1.1 200 OK" cursock wsl
  s" Content-Type: text/html; charset=utf-8" cursock wsl
  s" Connection: close" cursock wsl
  s" " cursock wsl
;
: send-204 ( -- )
  s" HTTP/1.1 204 No Content" cursock wsl
  s" Connection: close" cursock wsl
  s" " cursock wsl
;
: send-404 ( -- )
  s" HTTP/1.1 404 Not Found" cursock wsl
  s" Content-Type: text/plain" cursock wsl
  s" Connection: close" cursock wsl
  s" " cursock wsl
  s" not found" w
;

\ --- static file serving ---------------------------------------------

8192 buffer: xferbuf
96 buffer: extbuf

: mime-for ( a n -- a2 n2 )
  2dup s" .css" compare 0= if 2drop s" text/css" exit then
  2dup s" .js" compare 0= if 2drop s" text/javascript" exit then
  2dup s" .html" compare 0= if 2drop s" text/html; charset=utf-8" exit then
  2dup s" .json" compare 0= if 2drop s" application/json" exit then
  2drop s" application/octet-stream"
;

\ Scan backward for the LAST '.' (same lesson from the 4tH port: a
\ forward scan would hit the dots in a "../public/..." prefix first).
: file-ext ( a n -- a2 n2 )
  { a n }
  n 0 ?do
    a n 1- i - + c@ [char] . = if
      a n 1- i - + i 1+ unloop exit
    then
  loop
  a n
;

: serve-file ( path-a path-n -- )
  { pa pn }
  pa pn r/o bin open-file if
    drop send-404 exit
  then
  { fid }
  s" HTTP/1.1 200 OK" cursock wsl
  s" Content-Type: " w pa pn file-ext mime-for w cursock wsl
  s" Connection: close" cursock wsl
  s" " cursock wsl
  begin
    xferbuf 8192 fid read-file throw dup
  while
    xferbuf over cursock ws
  repeat drop
  fid close-file throw
;

\ --- path splitting -----------------------------------------------------

0 Value s1a 0 Value s1n
0 Value s2a 0 Value s2n
0 Value s3a 0 Value s3n
96 buffer: s1buf 96 buffer: s2buf 96 buffer: s3buf
1 buffer: slbuf  char / slbuf c!
: sl$ ( -- a n ) slbuf 1 ;

: split-path ( a n -- )
  dup 0> if over c@ [char] / = if 1 /string then then
  sl$ split2 { r1a r1n } { f1a f1n }
  f1a f1n s1buf place s1buf count to s1n to s1a
  r1a r1n sl$ split2 { r2a r2n } { f2a f2n }
  f2a f2n s2buf place s2buf count to s2n to s2a
  r2a r2n s3buf place s3buf count to s3n to s3a
;

: get-id ( -- id ) s2a s2n str>num ;

\ --- route handlers --------------------------------------------------

: do-page ( -- ) send-200 view-page ;

96 buffer: qvalbuf
: do-search ( -- )
  0 qvalbuf c!
  query-a query-n
  begin dup 0> while
    amp$ split2 { aa an } { pa pn }
    pa pn eq$ split2 { va vn } { ka kn }
    ka kn url-decode s" q" compare 0= if
      va vn url-decode qvalbuf place
    then
    aa an
  repeat 2drop
  qvalbuf count search-store
  send-200 view-search-list
;

: do-row ( -- )
  get-id find-idx { idx }
  idx -1 = if send-404 exit then
  send-200 idx view-row
;

: do-edit ( -- )
  get-id find-idx { idx }
  idx -1 = if send-404 exit then
  send-200 idx view-edit
;

: do-add ( -- )
  cursock read-body
  bodybuf ctlen parse-form
  fnamebuf count femailbuf count fphonebuf count add-contact
  send-200 view-list
;

: do-update ( -- )
  cursock read-body
  bodybuf ctlen parse-form
  get-id fnamebuf count femailbuf count fphonebuf count update-contact { idx }
  idx -1 = if send-404 exit then
  send-200 idx view-row
;

: do-delete ( -- )
  get-id remove-contact
  if send-204 else send-404 then
;

\ Reuses contacts.fs's lb-reset/lb-str line-builder buffer: safe here
\ since nothing else needs it during route dispatch.
: static-path ( -- a n )
  s1n 0= if s" ../public/index.html" exit then
  s1a s1n s" css" compare 0= if
    lb-reset s" ../public/css/" lb-str s2a s2n lb-str
    linebuf linelen exit
  then
  s1a s1n s" dist" compare 0= if
    lb-reset s" ../../dist/" lb-str s2a s2n lb-str
    linebuf linelen exit
  then
  lb-reset s" ../public/" lb-str s1a s1n lb-str
  linebuf linelen
;

: route ( -- )
  meth-a meth-n s" GET" compare 0= if
    s1a s1n s" contacts.html" compare 0= if do-page exit then
    s1a s1n s" contacts" compare 0= if
      s2n 0= if do-search exit then
      s3n 0= if do-row exit then
      s3a s3n s" edit" compare 0= if do-edit exit then
      send-404 exit
    then
    static-path serve-file exit
  then
  meth-a meth-n s" POST" compare 0= if
    s1a s1n s" contacts" compare 0= if do-add else send-404 then exit
  then
  meth-a meth-n s" PUT" compare 0= if
    s1a s1n s" contacts" compare 0= if do-update else send-404 then exit
  then
  meth-a meth-n s" DELETE" compare 0= if
    s1a s1n s" contacts" compare 0= if do-delete else send-404 then exit
  then
  send-404
;

\ --- connection handling + main loop -----------------------------------

: handle ( sock -- )
  to cursock
  cursock read-req-line
  cursock read-headers
  path-a path-n split-path
  ['] route catch drop
  cursock close-socket
;

: serve ( port -- )
  { port }
  seed-defaults
  port create-server { server }
  server 16 listen
  ." Contacts demo (Gforth) listening on http://localhost:" port . ." /contacts.html" cr
  begin
    server accept-socket { sock }
    sock ['] handle catch drop
    clearstack  \ belt-and-suspenders: this is a long-running loop, so
                \ any per-request stack imbalance (ours or a mismeasured
                \ one -- gforth's locals interact with the data stack in
                \ ways that make piecemeal DEPTH-diffing unreliable while
                \ locals are active) must never accumulate across requests.
  again
;
