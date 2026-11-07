\ util.fs -- request parsing: URL-decoding, header line splitting

: hexdigit ( c -- n )
  dup [char] 0 >= over [char] 9 <= and if [char] 0 - exit then
  dup [char] A >= over [char] F <= and if [char] A - 10 + exit then
  dup [char] a >= over [char] f <= and if [char] a - 10 + exit then
  drop 0
;
: hex2 ( c1 c2 -- byte ) { c1 c2 } c1 hexdigit 16 * c2 hexdigit + ;

256 buffer: decbuf
0 Value declen
: decc ( c -- ) decbuf declen + c! declen 1+ to declen ;

\ Decode an application/x-www-form-urlencoded string: '+' -> space,
\ '%XX' -> byte XX, everything else verbatim.
0 Value da
: url-decode ( a n -- a2 n2 )
  0 to declen
  begin dup 0> while
    over c@ [char] + = if
      bl decc 1 /string
    else over c@ [char] % = if
      dup 3 >= if
        over to da
        da 1+ c@ da 2 + c@ hex2 decc
        3 /string
      else
        over c@ decc 1 /string
      then
    else
      over c@ decc 1 /string
    then then
  repeat 2drop decbuf declen
;

: starts? ( a n pfx-a pfx-n -- flag )
  { a n pa pn }
  n pn < if false exit then
  a pn pa pn compare 0=
;
