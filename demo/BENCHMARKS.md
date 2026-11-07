# Contacts demo: server port benchmarks

Informal `ab -n 10000 -c 100 http://localhost:<port>/contacts.html` runs
against the ports of the Contacts demo (Node `demo/server.mjs`,
PicoLisp `demo/picolisp/`, Tcl `demo/tcl/`, Zig `demo/zig/`, 4tH
`demo/4th/`, Gforth `demo/gforth/`), all serving from the same seeded
contact data on one machine. Numbers are from a single run each, not
averaged over multiple trials -- treat as directional, not precise.

## Final standings

| Server | Req/s | Mean latency | p99 | Failed |
|---|---|---|---|---|
| **Zig (16-thread pool)** | **11798** | 8.5 ms | 13 ms | 0 |
| PicoLisp (optimized) | 8126 | 12.3 ms | 18 ms | 0 |
| Node (template caching fixed) | 6493 | 15.4 ms | 33 ms | 0 |
| Tcl (nonblocking I/O) | 5682 | 17.6 ms | 25 ms | 0 |
| 4tH (socat + process-per-request) | 1549 | 64.6 ms (mean; p50 4ms, p99 1047ms) | 1047 ms | 0 |
| Gforth (sequential accept loop) | 388 | 258 ms (mean; p50 45ms) | 81 ms (max) | 0 |

4tH and Gforth are both Forths but sit in very different places. 4tH is
a different architectural class from the other four (see "The 4tH
port" below) -- a brand-new OS process per request (`socat` forks and
execs a fresh `4th` interpreter for every connection) -- so its number
measures process-spawn overhead as much as request handling. Note the
gap between p50 (4ms -- genuinely fast once running) and p99/max
(1047ms/6446ms) -- under -c 100 concurrency, process creation itself
becomes the bottleneck, not the Forth code.

Gforth, by contrast, is architecturally identical to Node/Tcl/PicoLisp/
Zig -- one persistent process, a real socket listener, an in-memory
store -- and its 10000/10000 requests all genuinely succeeded with no
process-per-request subsidy. It's just slow in absolute terms: a
single-threaded sequential accept loop (so `-c 100` queues 99 requests
behind whichever one is running) combined with one `send()` syscall per
`write-socket` call -- and the view layer makes dozens of those per
page (see "The Gforth port" below for why that wasn't fixed with a
buffer, unlike the other interpreted ports).

## Sequential architectures degrade sharply under system-wide load

Running all six benchmarks back-to-back on the same machine (rather
than each in isolation) surfaced something the per-port numbers above
don't show: 4tH and Gforth -- the two ports with no concurrency model
at all, just one request handled fully before the next begins -- both
got *worse*, not just slower, when the other five servers were also
running and competing for CPU:

| Server | Req/s, isolated | Req/s, all six running | Failed, all six running |
|---|---|---|---|
| 4tH | 1549 | 349 | 0 (but p99 1028ms, max 28659ms) |
| Gforth | 388 (single isolated run) / 462 (clean re-run) | n/a -- see below | **2 runs failed outright** |

Gforth's first two attempts while the other five servers were still up
didn't just slow down -- `ab` gave up entirely with `apr_socket_recv:
Connection reset by peer` after roughly 6500-7000 of the 10000
requests. The server itself never crashed or corrupted anything --
`curl` got a normal `200` the moment I checked it afterward, and a
later isolated re-run (nothing else running) completed cleanly at
0/10000 failures. What happened is starvation, not a bug: with a
single-threaded, purely sequential `accept → read → write → close →
accept` loop and no event loop or OS threads to fall back on, if the
kernel scheduler doesn't get back around to Gforth's one process for
long enough -- because four other interpreters and a compiled binary
are all also demanding CPU -- a client that's been waiting since before
that stall will simply time out and disconnect, and there's no second
code path running concurrently to have served it instead.

4tH shows the same pattern for the same structural reason (`socat`
forking a brand-new `4th` interpreter per connection is just as
sequential-per-connection, with process-creation added on top): its
throughput under contention (349 req/s) is less than a quarter of its
isolated number (1549 req/s), and its worst-case latency balloons to
28.6 seconds, even though it happened not to drop any requests outright
this particular run.

The other four ports -- Node (event loop), Tcl (now fully non-blocking
I/O), PicoLisp (single-threaded but fast enough per-request that
starvation windows stay short), and Zig (an actual thread pool) -- show
no analogous failure mode in this series: each has *some* way to make
progress on, or quickly cycle through, other work while one operation
is in flight. The lesson generalizes past Forth specifically: a server
with zero concurrency primitives is one noisy neighbor away from
timing out live clients, regardless of how fast it is when it has the
machine to itself.

## CPU and memory, isolated runs

Each server benchmarked alone (not concurrently with the others, to keep
CPU accounting clean): same `ab -n 10000 -c 100` run, process's own CPU
ticks read from `/proc/<pid>/stat` (summed across `/proc/<pid>/task/*/stat`
for Zig, which is multi-threaded) before and after, converted to seconds
at `HZ=100`; memory is `VmHWM` (peak resident set size since process
start) from `/proc/<pid>/status` read immediately after the run.

| Server | Req/s | CPU-seconds / 10k reqs | CPU-ms / req | Peak RSS |
|---|---|---|---|---|
| Zig (16-thread pool) | 10317 | 1.38 | 0.138 | 5.5 MB |
| PicoLisp | 7692 | 1.29 | 0.129 | 6.4 MB |
| Tcl | 5564 | 1.70 | 0.170 | 5.5 MB |
| Node | 5998 | 1.92 | 0.192 | 136.5 MB |
| Gforth | 385 | 15.93 | 1.593 | 8.4 MB |

Notes:
- Gforth's CPU-seconds is an order of magnitude above every other
  port, consistent with its req/s: syscall-per-write-call plus a bytecode
  interpreter is a real cost, not just a benchmark artifact. Memory
  stays lean (8.4 MB) -- the interpreter overhead shows up as CPU time,
  not as a bigger process, matching the other lightweight C-based
  runtimes (Tcl, PicoLisp, Zig) rather than Node's V8 baseline.
- Req/s differs slightly from the "Final standings" table above because
  these were re-run one at a time (no contention from the other three
  servers sharing the machine), rather than all four running at once.
- Node's RSS is dominated by the V8/Node runtime baseline, not by this
  tiny app or the request load -- it's roughly the same whether Node is
  idle or serving traffic.
- PicoLisp edges out Zig on CPU-seconds despite being an interpreter;
  Zig's number includes the fixed overhead of 16 live pool threads
  (idle condition-variable waits are cheap, but 17 threads vs. 1-4 for
  the others is still more scheduler bookkeeping per request serviced).
- Tcl and Zig tie on peak RSS; both are lean C-level runtimes with a
  tiny in-memory store.

## Progression

### Initial baseline (blocking Tcl server, first three ports)
| Server | Req/s |
|---|---|
| Tcl | 5432 |
| Node | 2270 |
| PicoLisp | 2297 |

### After fixing Node's Eta `cache: false` (recompiled every template on every request)
| Server | Req/s |
|---|---|
| Node | 6460 → 6532 |
| Tcl | 5843 |
| PicoLisp | 2297 |

### After switching Tcl to fully event-driven (nonblocking) I/O
No throughput change on localhost (request data arrives all at once either
way) -- the fix was about not letting one slow client stall others, not
raw speed. Confirmed via `ab`: ~5800 req/s, 0 failures, unchanged.

### After optimizing the PicoLisp port
Three changes: cache the static page shell (previously rebuilt via the
tag-function machinery on every request), fast-path `ht:esc` to skip
escaping when a string has no special characters, and tokenize the
per-row template once at load time instead of rebuilding it per contact.
| Stage | Req/s |
|---|---|
| Before | 2297 |
| + cached page shell + `ht:esc` fast path | 4090 |
| + tokenized row rendering | 8083 → 8140 |

### Zig port added (thread-per-connection)
| Server | Req/s |
|---|---|
| PicoLisp | 8140 |
| Node | 6532 |
| Zig (1 thread per connection) | 5439 |
| Tcl | 5756 |

Thread-per-connection's OS thread creation/teardown cost dominated a
handler this cheap, despite Zig being the only compiled, GC-free runtime
here.

### Zig switched to a fixed 16-thread worker pool
First attempt used `pop()` (LIFO) on the shared queue, which under
`ab`'s sustained load let newer connections keep cutting ahead of older
queued ones -- starved a handful of requests past `ab`'s timeout
(`apr_pollset_poll` errors, incomplete run). Fixed by switching to FIFO
(`orderedRemove(0)`).
| Stage | Req/s | Failed |
|---|---|---|
| Thread-per-connection | 5439 | 0 |
| Pool, LIFO queue (bug) | -- | run didn't complete (timeout) |
| Pool, FIFO queue (fixed) | **11798** | 0 |

## Notable bugs found and fixed along the way

- **Tcl `split`** treats its second argument as a *character set*, not a
  literal substring -- `parseMultipart`'s boundary splitting silently
  truncated form field values whenever the random multipart boundary
  happened to contain a letter also present in the field value (editing
  a contact produced garbled values).
- **Node/Eta** `cache: false` recompiled every template (layout +
  includes) from disk on every single request.
- **PicoLisp**: page shell and per-row markup were rebuilt from scratch
  through the tag-function machinery on every request even though most
  of it never changes between requests.
- **Zig `takeDelimiterExclusive`** does not consume the delimiter byte
  itself (only `*Inclusive` does) -- naive line-at-a-time header parsing
  desynced after the request line, silently zeroing `Content-Length` on
  every POST/PUT body.
- **Zig worker pool**: LIFO queue pop starves old work under sustained
  load; must be FIFO for a request queue.
- **4tH `mime-for`**: used `drop` instead of `2drop` to clear a leftover
  `2dup`'d pair, underflowing the stack on every static-file request.
- **4tH `file-ext`**: scanning forward for the first `.` found the dots
  in a `"../public/..."` relative path prefix before ever reaching the
  actual file extension's dot. Fixed by scanning backward for the last
  `.` instead.
- **4tH request/arg pointers**: both `path-a`/`path-n` (from
  `bl parse-word`) and the datafile path (from `1 args`) point into
  buffers 4tH reuses on the next call -- by the time they were actually
  read (after `read-headers`'s repeated `refill`s, or at the very end of
  the request for `save-store`), the bytes had been overwritten by
  unrelated later reads. Same root cause as the Zig `Reader` buffer bug
  above, different language. Fixed by copying into dedicated buffers
  immediately after each value is produced.
- **4tH `CASE`/`OF`/`ENDOF`/`ENDCASE`**: leaves a residual stack
  imbalance specifically when code falls through two or more failed
  `OF` comparisons to reach the default branch (confirmed with a
  minimal standalone repro, independent of the rest of this codebase).
  `html-esc` was rewritten with a plain `IF/ELSE` chain instead.
- **Gforth `CASE`/`OF`** has the *same* fallthrough-stack-imbalance
  quirk as 4tH's -- confirmed independently with its own minimal
  repro, in a completely different Forth implementation. Avoided the
  same way, with a plain `IF/ELSE` chain.
- **Gforth buffer-reuse pointers, twice over**: `path-a`/`path-n`
  parsed from the request line pointed into a shared line-read buffer
  that the next `read-line` call (reading headers) overwrote before
  they were used -- same bug class as the Zig `Reader`/4tH
  buffer-reuse bugs above, a third language in. Separately, a result
  from Gforth's own `1 args`-equivalent path handling also pointed into
  a volatile buffer. Both fixed by copying into dedicated buffers
  immediately, the same fix pattern as every other port that hit this.
- **Gforth `write-socket` on a filename mistake**: an early `write-line`
  call against a socket-derived file-id crashed with "Invalid memory
  address" -- traced to a stray `dup` duplicating only the *length*
  half of an `(addr len)` pair before the call, not a full `2dup`,
  leaving `write-line` reading a length value as if it were an address.
- **Gforth `read-line` return value confusion**: `read-line`'s ANS
  signature returns the *count* read, not the buffer address -- a
  first draft blindly `type`'d the two values `read-line` leaves on the
  stack (count, flag) as if they were `(addr len)`, handing `TYPE` a
  boolean flag as a string length and corrupting memory on read.
- **Gforth `static-path`/`file-ext`**: initially built file paths by
  interleaving `PLACE` calls into `PAD` with `PAD COUNT` calls that
  don't compose the way `S"`-style concatenation does; rewritten using
  a small dedicated line-builder buffer (the same `lb-str`/`lb-reset`
  idiom already used for the record store) instead of abusing `PAD`.
- **Gforth persistent-store corruption via search**: the search/filter
  logic was ported from 4tH's `apply-search`, which overwrites the live
  record array with the filtered results -- harmless in 4tH's
  process-per-request model (the process exits right after responding,
  so clobbering its own copy of the store changes nothing persistent),
  but a real bug in Gforth's long-lived server: the *first* search
  request would have permanently and silently shrunk the in-memory
  store to just that query's matches, corrupting it for every
  subsequent request for the life of the process. Caught before it
  shipped by noticing the architecture had changed out from under a
  copy-pasted assumption. Fixed by rendering search results from a
  separate scratch buffer (`sresults`/`sfcount`) that's never copied
  back into the live `records`/`nc`.
- **Gforth per-request stack leak**: a `header-value` helper returned
  an unused `(addr len)` pair on its "no match" path that the caller
  never discarded, leaking 4 cells into the data stack on every header
  line that matched neither `Content-Length` nor `Content-Type` (i.e.
  almost every header, every request). With `ab -c 100`, this
  overflowed the data stack after roughly 160 requests and killed the
  server mid-benchmark. Partially fixed by discarding the pair
  properly; also hardened with a `clearstack` call between connections
  in the main accept loop as a deliberate belt-and-suspenders measure,
  since Gforth's locals appear to interact with the data stack in ways
  that made further piecemeal `DEPTH`-diffing unreliable to fully trust.

## The 4tH port

4tH (`demo/4th/contacts.4th`) is a genuinely different architecture from
the other four, forced by the language itself: 4tH has **no socket
words at all** -- confirmed both in its manual and by grepping its C
source for `socket`/`bind`/`listen`/`accept(2)` (the Forth word
`ACCEPT` is unrelated -- it just reads a line of input). The only
networking model 4tH's own documentation offers is the one demonstrated
by its bundled `4th/web4th.4th` example: run under `inetd`, so the
OS/`inetd` does the listening and hands the program a socket already
wired to stdin/stdout. `demo/4th/run.sh` reproduces that with `socat`
(`TCP-LISTEN:PORT,fork EXEC:'4th cxq contacts.4th contacts.dat'`) instead
of a real `inetd.conf` entry, since that's installable in a sandbox.

This has two consequences the other ports don't share:

- **No persistent process, so no in-memory store.** Each request is a
  brand-new `4th` interpreter invocation with nothing alive from the
  last one. The contact list is instead a flat file (`contacts.dat`,
  one record per line, fields separated by ASCII 31) read fully at the
  start of a request and rewritten fully at the end if the request
  mutated it. Concurrent writers can race -- there's no `flock` in 4tH
  -- accepted and documented rather than solved, same spirit as the
  other ports' documented shortcuts.
- **POST/PUT (routes with a request body) hang over a real socket.**
  This was found the hard way: everything worked perfectly when 4tH was
  driven directly via a shell pipe (`printf ... | 4th cxq contacts.4th`)
  for every route including POST and PUT, but POST/PUT specifically hung
  forever once wired through `socat` to a real TCP client (`curl`,
  `ab`). Root cause: 4tH's `ACCEPT` word (used to read exactly
  `Content-Length` bytes) is line-buffered -- it blocks until it sees a
  newline or the stream hits EOF. A pipe fed by `printf` closes (EOF)
  the instant the data's sent, which `accept` happily treats as "done."
  A live socket never does that -- the client (correctly) keeps the
  connection open waiting for the response -- so if the POST body has no
  trailing newline (the normal case), `accept` just waits forever for a
  newline that will never arrive. No lower-level raw-byte-count socket
  read was found in 4tH to work around this. GET and DELETE (no body)
  are completely unaffected and work correctly over real sockets, which
  is why they're what's benchmarked above and exercised in the
  functional tests below -- POST/PUT are verified only via direct pipe
  invocation, not through `run.sh`.

## The Gforth port

Gforth (`demo/gforth/`) is a different Forth from 4tH in one decisive
way: it has a real socket library (`unix/socket.fs`, backed by an
actual compiled C extension exposing `socket`/`bind`/`listen`/`accept`/
`send`/`recv` directly) and its `READ-LINE`/`READ-FILE` behave exactly
to the ANS standard on a socket-derived file-id as on a regular file --
confirmed directly by reproducing 4tH's exact failure mode (reading a
fixed-length, non-newline-terminated POST body over a real, open TCP
connection) and watching it *not* hang. That one capability is the
difference between "needs `socat` and a CGI-style re-architecture" and
"is a normal standalone server, same shape as Node/Tcl/PicoLisp/Zig":
one persistent process, a `create-server`/`listen`/`accept-socket`
loop, and an in-memory store that survives across requests.

Two implementation choices worth calling out:

- **No output buffer, no `Content-Length`.** Every view word streams
  straight to the client socket via `write-socket` as it's generated,
  the same convention Gforth's own bundled `httpd.fs` example uses for
  dynamic content. `Connection: close` plus actually closing the
  socket is the framing; `curl`/`ab` read until EOF and don't need the
  header. This sidesteps needing any of the other ports' output-buffer
  machinery entirely, at the cost of one `send()` syscall per
  `write-socket` call -- which is also most of why it's slow (see
  below).
- **A global "current socket" convention in the view layer.** Every
  view word would otherwise need to thread a `sock` parameter through
  dozens of calls (`w`/`wq`/`wn`/`we` for write-string/write-quote/
  write-number/write-escaped). Since connections are handled strictly
  one at a time, a single `cursock` value set once per connection and
  read implicitly by all the write helpers is safe and cuts the
  boilerplate dramatically -- the views file reads close to the plain
  string-template style the Tcl port uses, just streamed instead of
  built as one string.

Why it's slow (388 req/s, far behind every other port including 4tH's
GET path): two independent costs, neither of which is "the language is
slow" in the way that's usually meant. First, the accept loop is
strictly sequential -- one `begin accept-socket handle again` loop with
no threads and no event-driven I/O multiplexing -- so under `ab -c 100`,
99 connections queue up behind whichever one is currently running, and
each one runs to completion at Gforth's own interpreted speed before
the next even starts being read. Second, and probably larger: the view
layer's direct-streaming design means a full `/contacts.html` page
makes on the order of a hundred separate `write-socket` calls (one or
more per HTML attribute and text fragment), each a real `send(2)`
syscall -- there's no buffering to coalesce them, by design (see
above). PicoLisp and Tcl hit variants of this same per-call-overhead
problem and fixed it by building the response into one string first,
then writing it once; Gforth's port doesn't, so it pays a syscall tax
the compiled/buffered ports don't. Both costs are addressable (a
thread-or-process-per-connection model and/or an output buffer, mirroring
fixes already made elsewhere in this series) but weren't attempted here,
given how much of this port's effort already went into getting the
request-parsing layer *correct* over a real socket -- something no
other Forth attempt in this series achieved at all.

## Code complexity

### Lines of code

| | contacts.* | router.* | util.* | server/views | Total |
|---|---|---|---|---|---|
| **Node** | 49 | 37 (shared) | 69 (shared) | ~17 routes + 7 (views.mjs) + 92 (eta templates) | ~158 app-specific, on 113 shared infra |
| **Tcl** | 86 | 57 | 155 | 224 (server) + 115 (views) | 637 |
| **PicoLisp** | 72 | 48 | 161 | 157 (server) + 126 (html.l) + 180 (views) | 744 |
| **Zig** | 176 | 63 | 146 | 291 (server) + 103 (views) | 779 |
| **4tH** | one 659-line file (no module split -- see note) | | | | 659 + 28 (run.sh) |
| **Gforth** | 188 | n/a (routing lives in server.fs) | 41 | 333 (server) + 127 (views) | 689 + 30 (run.sh) |

Node's number isn't directly comparable to the other three: `router.mjs`
and `util.mjs` are shared across all six demo apps (chat, bot, dashboard,
snake, contacts, items), so contacts itself only costs ~158 lines riding
on amortized infrastructure someone else already wrote. Tcl, PicoLisp,
and Zig each had to build their own HTTP server, router, and form/
multipart parser from nothing -- that cost of entry (461-603 lines before
any contacts-specific logic) dwarfs the actual domain logic (72-176
lines) in all three, by 4-5x. 4tH's 659 lines cover the same ground
(store, routing, views, request parsing) in one file -- no particular
reason to split it given the language's lack of a module system beyond
plain `include`, and the line count is misleading on its own: see below
for why the *density* of actual debugging effort per line was far
higher here than the raw count suggests.

### Qualitative complexity, easiest to hardest

**Node -- lowest friction.** Dynamic typing, GC, a real templating
library (Eta) doing escaping/includes/layout for free, no manual memory
or concurrency model to reason about. The one bug found (`cache: false`)
wasn't a porting bug at all -- a pre-existing perf foot-gun, one config
flag to fix. If a router/util layer already exists in your stack, adding
an app is trivial.

**PicoLisp -- concise but conceptually dense.** Fewest raw lines of
domain logic, but getting there required understanding a bespoke
tag-function DSL (`curry`/`apply`/`mapcar` metaprogramming in `html.l`)
before touching the actual app. Zero outright bugs during the port --
but reaching good performance required real engineering, not a
config flag (see below).

**Tcl -- simple surface, one sharp landmine.** `socket`/`fileevent`/`dict`
cover most of what's needed with little ceremony, and the initial
blocking version was almost boilerplate. Two real traps: `split`'s second
argument is a *character set*, not a substring -- a classic gotcha that
silently corrupted multipart form data -- and making the server fully
non-blocking meant hand-rolling a byte-accumulating state machine (no
async/await to lean on). Moderate complexity, concentrated in I/O
plumbing rather than app logic.

**Zig -- highest complexity by a wide margin.** Three compounding
sources: (1) the std library itself was unfamiliar and still settling --
`std.Io` is a brand-new interface as of 0.16, requiring reading compiler
source live rather than recalling an API; (2) manual memory ownership --
every stored string needs an explicit dupe/free discipline to avoid a
use-after-free once requests run on separate threads, something no other
port has to think about; (3) real concurrency -- a hand-rolled
mutex+condvar worker pool, because `std.Thread.Pool` doesn't even exist
in this version. Also the port with the most genuine bugs:
`takeDelimiterExclusive` silently not consuming its delimiter (desynced
every header read), `allocRemaining`'s limit semantics causing
`StreamTooLong` on static files, and the LIFO-vs-FIFO pool starvation bug
above. None of these failed loudly -- each needed `/proc`-level or
stdlib-source-level debugging to find.

**4tH -- highest complexity of all, for a different reason than Zig.**
Zig's difficulty was a large, unfamiliar, powerful standard library;
4tH's difficulty was the opposite -- a small, old, idiosyncratic one
with almost no stack-safety net and no architecture fit for the job
(see "The 4tH port" above: no sockets, forcing the whole
`socat`-exec-per-request design, and a body-read primitive that turns
out not to work on live sockets at all). Nearly every primitive had an
undocumented sharp edge that only surfaced experimentally: `ALLOT` was
removed from the language entirely (use `buffer:`); `place`/`compare`
looked built-in but needed explicit `include`s; `CASE`/`OF` corrupts the
stack on certain fallthroughs; `open` fully consumes the filename
string instead of leaving a copy, unlike nearly every other
stack-effect in the language; and `args`/`parse-word` results point
into buffers that silently rot by the time they're used later in the
same request. None of these raised a compile error -- each was a
silent stack-depth or stale-pointer bug requiring the same
build-a-minimal-repro, bisect-the-file discipline, over and over, far
more often per line of code than any other port in this series.

**Gforth -- high complexity, but of a more "normal" kind than either
Forth sibling.** Having a real socket library and ANS-standard locals
(`{ a b c }`) removed the two biggest sources of 4tH's pain --
no CGI-architecture detour, and far less raw stack-position juggling,
since named locals replace most of the scratch-value and stack-shuffle
discipline 4tH required throughout. What was left were bugs that read
as ordinary porting mistakes rather than language sharp edges: a
mixed-up `dup` vs `2dup`, misreading `READ-LINE`'s return signature,
abusing `PAD` across calls that don't compose that way. The one
genuinely sui generis bug -- and the one that actually took the server
down -- was the persistent-store corruption risk in porting 4tH's
search logic verbatim into a long-lived process (see the bugs list and
"The Gforth port" above): a correctness bug that had nothing to do
with Forth's syntax and everything to do with carrying an assumption
(each request is a fresh process, so mutating shared state is free)
across an architecture change without re-deriving it. That's a mistake
any port could have made; it just happened to surface here because
Gforth was the first Forth in this series capable of staying up long
enough for "shared state" to mean anything.

### Why PicoLisp needed real engineering to get fast, not just a flag

Node's fix was flipping `cache: true` -- a knob the templating library
already provided, built by someone else, for exactly this problem.
PicoLisp's `html.l` tag-function builder has no such cache option; there
was nothing to turn on. The caching mechanism had to be invented from
scratch, for two reasons:

- **The cost is structural, not accidental.** `<div>`, `<button>`, etc.
  aren't cheap wrappers -- each call builds an attribute cons-list,
  recurses through `ht:render`'s type-dispatch (`cond` over
  fragment/string/list), and joins children via `mapcar` + `apply` +
  `pack`. That's real allocation and interpretive dispatch on every tag,
  every request, with no bytecode-to-native compilation or JIT to
  amortize it away.
- **Finding it required profiling, not reading.** `v:page` *looked*
  fine. The bottleneck only surfaced by writing a standalone PicoLisp
  benchmark loop timing `v:page` in isolation and comparing it to the
  observed per-request latency -- a step none of the other ports needed,
  since their bottlenecks (a boolean flag, a `split` semantics bug, an
  unset backlog) were visible from the code or the symptom directly.

The fix itself was two bespoke techniques, not a configuration: caching
the static page shell around a placeholder marker (built once, `pack`ed
around the dynamic list per request), and -- for the row-rendering hot
path -- rendering one row against fake marker values at load time,
tokenizing the output into literal-chunks + marker-symbols, then doing a
flat `mapcar` substitution per request instead of going through the tag
machinery at all. That second trick is architecturally invasive:
`v:rowFast` doesn't configure or extend `v:row`, it bypasses it entirely,
duplicating intent in two places. It only works because a contact row's
markup happens to be fixed-shape with exactly four varying values -- a
property that had to be noticed and exploited, not something the
framework handed over for free.

So: low line count to write the feature, but reaching competitive speed
meant building custom infrastructure that doesn't exist anywhere else in
the codebase -- a cost the other three ports never paid, because their
performance problems had an off-the-shelf fix (a flag, an I/O redesign
using stdlib primitives, a backlog number).
