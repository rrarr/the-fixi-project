#!/usr/bin/env pil
# server.l -- PicoLisp port of demo/server.mjs for the Contacts demo.
# A stateless HTTP server over raw sockets: each request is parsed,
# dispatched by (method path) to a handler, and answered with a plain
# HTML response -- no PicoLisp sessions/`app`, since all interactivity
# is delegated to fixi on the client.
#
# Run:  pil demo/picolisp/server.l -main +   (or: ./run.sh [port])

(load "util.l")
(load "router.l")
(load "views.l")

(setq *Root (pack (car (file)) "../.."))   # repo root, two levels up from demo/picolisp/

# --- request parsing ---------------------------------------------------

# (line T) reads one line and strips the trailing CRLF/LF for us.
(de s:readLine ()
   (line T) )

(de s:readHeaders ()
   (make
      (let L (s:readLine)
         (while (and L (<> L ""))
            (let I (index ":" (chop L))
               (when I
                  (link
                     (cons
                        (lowc (pack (head (dec I) (chop L))))
                        (pack (clip (chop (pack (tail (- I) (chop L))))) ) ) ) ) )
            (setq L (s:readLine)) ) ) ) )

(de s:header (Headers Name)
   (cdr (assoc Name Headers)) )

# Read Len bytes of text body. Content-Length is a byte count; this
# assumes ASCII form bodies, which is what fixi/browsers send here.
#
# NOTE: this reads via `rd` (which reads Len raw bytes as one big-endian
# number) and reconstructs the text byte-by-byte, rather than looping
# `(char)` Len times. Looping `(char)` all the way to exactly the last
# available byte on a socket was found empirically (while building this)
# to leave the connection in a state where the response written right
# after never reaches the client -- `rd` doesn't have that problem.
(de s:readBody (Len)
   (let N (rd Len)
      (pack
         (make
            (for I Len
               (link (char (& 255 (>> (* 8 (- Len I)) N)))) ) ) ) ) )

(de s:handle (Sock)
   (in Sock
      (let L (s:readLine)
         (when (and L (<> L ""))
            (let Parts (split (chop L) " ")
               (let
                  (Method (uppc (pack (car Parts)))
                     Full (pack (cadr Parts))
                     Headers (s:readHeaders) )
                  (let
                     (QPos (index "?" (chop Full))
                        Path (if QPos (pack (head (dec QPos) (chop Full))) Full)
                        Query
                           (if QPos
                              (u:parseForm (pack (tail (- QPos) (chop Full))))
                              NIL )
                        Len (let C (s:header Headers "content-length") (and C (format C)))
                        ContType (s:header Headers "content-type") )
                     (let
                        (Body (and Len (> Len 0) (s:readBody Len))
                           Boundary (and ContType (sub? "multipart/form-data" (lowc ContType)) (u:boundary ContType)) )
                        (list Method Path Query
                           (if Boundary
                              (u:parseMultipart Body Boundary)
                              (u:parseForm Body) ) ) ) ) ) ) ) ) ) )

# --- routes -------------------------------------------------------------

(route "GET" "/contacts.html"
   '((Sock Params Query Form)
      (u:sendHtml Sock (html (v:page (contacts:all)))) ) )

(route "GET" "/contacts"
   '((Sock Params Query Form)
      (u:sendHtml Sock (html (v:list (contacts:search (u:param Query "q"))))) ) )

(route "POST" "/contacts"
   '((Sock Params Query Form)
      (contacts:add (u:param Form "name") (u:param Form "email") (u:param Form "phone"))
      (u:sendHtml Sock (html (v:list (contacts:all)))) ) )

(route "GET" "/contacts/:id"
   '((Sock Params Query Form)
      (let C (contacts:find (u:param Params "id"))
         (if C
            (u:sendHtml Sock (v:rowFast C))
            (u:sendNotFound Sock) ) ) ) )

(route "GET" "/contacts/:id/edit"
   '((Sock Params Query Form)
      (let C (contacts:find (u:param Params "id"))
         (if C
            (u:sendHtml Sock (html (v:edit C)))
            (u:sendNotFound Sock) ) ) ) )

(route "PUT" "/contacts/:id"
   '((Sock Params Query Form)
      (let C
         (contacts:update (u:param Params "id")
            (u:param Form "name") (u:param Form "email") (u:param Form "phone") )
         (if C
            (u:sendHtml Sock (v:rowFast C))
            (u:sendNotFound Sock) ) ) ) )

(route "DELETE" "/contacts/:id"
   '((Sock Params Query Form)
      (contacts:remove (u:param Params "id"))
      (u:sendNoContent Sock) ) )

# --- static assets (css, the fixi client script) -----------------------

(de s:static (Sock Path)
   (cond
      ((pre? "/dist/" Path) (u:sendFile Sock (pack *Root Path)))
      ((= "/" Path) (u:sendFile Sock (pack *Root "/demo/public/index.html")))
      (T (u:sendFile Sock (pack *Root "/demo/public" Path))) ) )

# --- main loop -----------------------------------------------------------

(de serve (Port)
   (let Sd (port Port)
      # PicoLisp's `port` hardcodes a listen(2) backlog of 5 (lib/net.l);
      # under concurrent load that overflows, dropping SYNs and forcing
      # multi-second TCP retransmits. Raise it directly via the "listen"
      # syscall it already set up the socket for.
      (%@ "listen" 'I Sd 511)
      (prinl "Contacts demo (PicoLisp) listening on http://localhost:" Port "/contacts.html")
      (loop
         # `listen` blocks via poll(2) until a connection is pending, then
         # calls `accept`; calling `accept` directly here would instead have
         # it busy-poll with a flat ~100ms usleep between retries (see
         # lib/net.l), adding up to 100ms of latency to every request.
         (let Sock (listen Sd)
            (when Sock
               (let Req (s:handle Sock)
                  (when Req
                     (let (Method (car Req) Path (cadr Req) Query (caddr Req) Form (cadddr Req))
                        (unless (r:dispatch Method Path Sock Query Form)
                           (if (= Method "GET")
                              (s:static Sock Path)
                              (u:sendNotFound Sock) ) ) ) ) )
               (close Sock) ) ) ) ) )

(de main ()
   (serve (or (format (opt)) 8766)) )
