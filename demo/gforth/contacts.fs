\ contacts.fs -- Gforth port of the Contacts demo. Unlike the 4tH port,
\ Gforth has a real socket library (unix/socket.fs) backed by an actual
\ C extension, so this is a true standalone persistent server with an
\ in-memory store, same architecture as the Node/Tcl/PicoLisp/Zig ports.

31 constant FS
1 buffer: fsbuf
FS fsbuf c!
: fs$ ( -- a n ) fsbuf 1 ;

: str>num ( a n -- n ) 0 0 2swap >number 2drop drop ;
: num>str ( n -- a n ) 0 <# #s #> ;

\ Split (a n) on a literal substring delimiter (delim-a delim-n) into
\ the part before it and the part after it (delimiter stripped). If not
\ found, before = the whole string, after = empty.
: split2 ( a n delim-a delim-n -- before-a before-n after-a after-n )
  { a n da dn }
  a n da dn search
  if
    { ma mn }
    a n mn - ma dn + mn dn -
  else
    a n a n + 0
  then
;

\ --- the store: one packed "id FS name FS email FS phone" record per slot

64 constant MAXC
256 constant /rec
MAXC /rec * buffer: records
: rec-slot ( i -- a ) /rec * records + ;

0 Value nc
1 Value next-id

256 buffer: linebuf
0 Value linelen
: lb-reset ( -- ) 0 to linelen ;
: lb-str ( a n -- ) dup >r linebuf linelen + swap cmove r> linelen + to linelen ;
: lb-num ( n -- ) num>str lb-str ;
: lb-chr ( c -- ) linebuf linelen + c! linelen 1+ to linelen ;

: put-rec ( na nn ea en pa pn id idx -- )
  { na nn ea en pa pn id idx }
  lb-reset
  id lb-num FS lb-chr
  na nn lb-str FS lb-chr
  ea en lb-str FS lb-chr
  pa pn lb-str
  linebuf linelen idx rec-slot place
;

0 Value id1
0 Value na 0 Value nn
0 Value ea 0 Value en
0 Value pha 0 Value phn

: fields-of ( slot-addr -- )
  count
  fs$ split2 { r1a r1n }          \ before = id string; after saved in r1a/r1n
  str>num to id1
  r1a r1n fs$ split2 { r2a r2n }  \ before = name; after (email FS phone) saved
  to nn to na
  r2a r2n fs$ split2 { r3a r3n }  \ before = email; after = phone, saved
  to en to ea
  r3a r3n to phn to pha
;
: rec-fields ( i -- ) rec-slot fields-of ;

: find-idx ( id -- idx )
  { id }
  -1 { result }
  nc 0 ?do
    result -1 = if
      i rec-fields id1 id = if i to result then
    then
  loop
  result
;

\ trim leading/trailing spaces -- each loop computes one combined flag
\ (length check AND space check) before its single WHILE, since a
\ begin/while/repeat can only test one flag per iteration.
: trim ( a n -- a2 n2 )
  begin
    dup 0> if over c@ bl = else false then
  while
    1 /string
  repeat
  begin
    dup 0> if 2dup + 1- c@ bl = else false then
  while
    1-
  repeat
;

0 Value ac-na 0 Value ac-nn
0 Value ac-ea 0 Value ac-en
0 Value ac-pa 0 Value ac-pn
: add-contact ( na nn ea en pa pn -- )
  { na nn ea en pa pn }
  na nn trim to ac-nn to ac-na
  ea en trim to ac-en to ac-ea
  pa pn trim to ac-pn to ac-pa
  ac-nn 80 min to ac-nn
  ac-en 80 min to ac-en
  ac-pn 40 min to ac-pn
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

0 Value uc-na 0 Value uc-nn
0 Value uc-ea 0 Value uc-en
0 Value uc-pa 0 Value uc-pn
: update-contact ( id na nn ea en pa pn -- idx )
  { id na nn ea en pa pn }
  id find-idx { idx }
  idx -1 = if idx exit then
  idx rec-fields
  na nn trim to uc-nn to uc-na
  uc-nn 0= if na nn to uc-nn to uc-na then
  uc-nn 80 min to uc-nn
  ea en trim to uc-en to uc-ea
  uc-en 80 min to uc-en
  pa pn trim to uc-pn to uc-pa
  uc-pn 40 min to uc-pn
  uc-na uc-nn uc-ea uc-en uc-pa uc-pn id1 idx put-rec
  idx
;

: remove-contact ( id -- flag )
  find-idx { idx }
  idx -1 = if false exit then
  nc 1- idx ?do
    i 1+ rec-slot count i rec-slot place
  loop
  nc 1- to nc
  true
;

\ --- search (case-sensitive substring match, same simplification 4tH made) --

: contains? ( a n pat-a pat-n -- flag )
  dup 0= if 2drop 2drop true exit then
  search nip nip
;

MAXC /rec * buffer: sresults
0 Value sfcount
: sres-slot ( i -- a ) /rec * sresults + ;

: search-store ( q-a q-n -- )
  { qa qn }
  0 to sfcount
  nc 0 ?do
    i rec-fields
    na nn qa qn contains?
    ea en qa qn contains? or
    pha phn qa qn contains? or
    if
      i rec-slot count sfcount sres-slot place
      sfcount 1+ to sfcount
    then
  loop
;

\ NOTE: deliberately no "apply-search" that copies results back into
\ records/nc -- unlike the 4tH port (a fresh process per request, so
\ clobbering its in-memory copy was harmless), this server is
\ long-lived and nc/records must never be mutated by a read-only
\ search. Rendering reads sresults/sfcount directly instead (see
\ view-search-row/view-search-list in views.fs).
