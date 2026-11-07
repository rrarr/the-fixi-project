# util.l -- request parsing and response helpers, equivalent to
# demo/lib/util.mjs (minus the parts server.l/router.l handle directly).

(de u:uriDecode (S)
   (let (L (chop S) R NIL)
      (while L
         (cond
            ((= "+" (car L)) (push 'R " ") (pop 'L))
            ((= "%" (car L))
               (pop 'L)
               (push 'R (char (hex (pack (pop 'L) (pop 'L))))) )
            (T (push 'R (pop 'L))) ) )
      (pack (flip R)) ) )

# Parse a "a=b&c=d" query/body string into an assoc list of (key . value)
(de u:parseForm (S)
   (make
      (for Pair (split (chop (or S "")) "&")
         (when Pair
            (let KV (split Pair "=")
               (link
                  (cons
                     (u:uriDecode (pack (car KV)))
                     (u:uriDecode (pack (apply append (cdr KV)))) ) ) ) ) ) ) )

(de u:param (Params Key)
   (cdr (assoc Key Params)) )

# --- substring helpers (char-list based) ------------------------------

# Returns the char-list tail right after the first occurrence of Needle
# in Hay (a char list), or NIL if Needle doesn't occur.
(de u:after (Needle Hay)
   (let (N (chop Needle) Len (length (chop Needle)))
      (u:afterLoop N Len Hay) ) )

(de u:afterLoop (N Len Hay)
   (cond
      ((not Hay) NIL)
      ((= N (head Len Hay)) (tail (- Len) Hay))
      (T (u:afterLoop N Len (cdr Hay))) ) )

# Returns the char-list prefix before the first occurrence of Needle
# in Hay (a char list), or NIL if Needle doesn't occur.
(de u:before (Needle Hay)
   (let (N (chop Needle) Len (length (chop Needle)))
      (u:beforeLoop N Len Hay NIL) ) )

(de u:beforeLoop (N Len Hay Acc)
   (cond
      ((not Hay) NIL)
      ((= N (head Len Hay)) (flip Acc))
      (T (u:beforeLoop N Len (cdr Hay) (cons (car Hay) Acc))) ) )

# Extract the boundary token from a "multipart/form-data; boundary=XXX"
# Content-Type header value, stripping surrounding quotes if present.
(de u:boundary (ContentType)
   (let Rest (u:after "boundary=" (chop ContentType))
      (when Rest
         (let B (pack Rest)
            (if (pre? "\"" B)
               (pack (head (- 1) (cdr (chop B))))
               B ) ) ) ) )

# Split a string into lines on "\n", stripping a trailing "\r" from each.
(de u:lines (S)
   (mapcar
      '((L) (if (and L (= "\r" (last L))) (pack (head (- 1) L)) (pack L)))
      (split (chop (or S "")) "\n") ) )

# Extract the "name" from a Content-Disposition header line, e.g.
# `Content-Disposition: form-data; name="email"` -> "email"
(de u:mpName (Hdr)
   (and (pre? "content-disposition" (lowc Hdr))
      (let Start (u:after "name=\"" (chop Hdr))
         (and Start
            (let End (u:before "\"" Start)
               (and End (pack End)) ) ) ) ) )

# Parse a multipart/form-data body into an assoc list of (name . value),
# for simple text fields (no file uploads) -- a direct port of the
# parseMultipart helper in demo/lib/util.mjs.
(de u:parseMultipart (Body Boundary)
   (u:mpScan (u:lines Body) (pack "--" Boundary)) )

(de u:mpScan (Lines Marker)
   (cond
      ((not Lines) NIL)
      ((<> (car Lines) Marker) (u:mpScan (cdr Lines) Marker))
      (T
         (let
            (Hdr (cadr Lines)
               Name (u:mpName (or Hdr ""))
               Rest (cddr Lines) )     # Rest should start with the blank line
            (if (not Name)
               (u:mpScan (cdr Lines) Marker)
               (let (Value NIL Tail (cdr Rest) End (pack Marker "--"))
                  (while (and Tail (<> (car Tail) Marker) (<> (car Tail) End))
                     (setq Value (cons (car Tail) Value))
                     (setq Tail (cdr Tail)) )
                  (cons
                     (cons Name (glue "\n" (flip Value)))
                     (u:mpScan Tail Marker) ) ) ) ) ) ) )

# --- HTTP response helpers -------------------------------------------

(de u:status (N)
   (case N
      (200 "200 OK")
      (204 "204 No Content")
      (404 "404 Not Found")
      (405 "405 Method Not Allowed")
      (T (pack N " ?")) ) )

(de u:sendHtml (Sock Html)
   (out Sock
      (prinl "HTTP/1.1 " (u:status 200) "\r")
      (prinl "Content-Type: text/html; charset=utf-8\r")
      (prinl "Content-Length: " (size Html) "\r")
      (prinl "Connection: close\r")
      (prinl "\r")
      (prin Html) ) )

(de u:sendNoContent (Sock)
   (out Sock
      (prinl "HTTP/1.1 " (u:status 204) "\r")
      (prinl "Connection: close\r")
      (prinl "\r") ) )

(de u:sendNotFound (Sock)
   (out Sock
      (prinl "HTTP/1.1 " (u:status 404) "\r")
      (prinl "Content-Type: text/plain\r")
      (prinl "Content-Length: 9\r")
      (prinl "Connection: close\r")
      (prinl "\r")
      (prin "not found") ) )

(de u:mime (Ext)
   (case Ext
      ("html" "text/html; charset=utf-8")
      ("js"   "text/javascript; charset=utf-8")
      ("css"  "text/css; charset=utf-8")
      ("map"  "application/json; charset=utf-8")
      (T "application/octet-stream") ) )

(de u:ext (Path)
   (let L (split (chop Path) ".")
      (if (> (length L) 1) (pack (last L)) "") )  )

(de u:sendFile (Sock Path)
   (if (not (info Path))
      (u:sendNotFound Sock)
      (let Bytes (in Path (till NIL T))
         (out Sock
            (prinl "HTTP/1.1 " (u:status 200) "\r")
            (prinl "Content-Type: " (u:mime (u:ext Path)) "\r")
            (prinl "Content-Length: " (size Bytes) "\r")
            (prinl "Connection: close\r")
            (prinl "\r")
            (prin Bytes) ) ) ) )
