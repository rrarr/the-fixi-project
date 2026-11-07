# html.l -- minimal standalone tag-function HTML builder, in the
# idiomatic PicoLisp "(<div> 'class ...)" style described at
# https://software-lab.de/doc/app.html, but implemented fresh here
# rather than pulling in @lib/form.l (which is entangled with
# PicoLisp's own stateful GUI/session framework that this demo is
# deliberately avoiding).
#
# Usage:
#   (<div> 'row (<span> NIL "hello"))
#     -> a *fragment* that renders to <div class="row"><span>hello</span></div>
#
#   (<input> '(("name" . "q") ("fx-trigger" . "search")))
#     -> renders to <input name="q" fx-trigger="search">
#
# The second argument ("Att") is either:
#   - NIL                      no class/attributes
#   - an atom (string/symbol)  used as the "class" attribute
#   - a list of (name . value) pairs   printed as literal attributes
#
# Any further arguments are children:
#   - a fragment (the result of another tag function) is spliced in as-is
#   - a plain string/symbol is treated as text and HTML-escaped
#   - a list of children (e.g. from mapcar over records) is rendered in order
#
# A "fragment" is just (ht:H . "<already-rendered-html>") -- the wrapper is
# what lets us tell "already-built markup" apart from "plain text that still
# needs escaping", both of which would otherwise just be picolisp strings.
# Use (html Frag) to unwrap a top-level fragment to its final string.

# Most field values (names, emails, phone numbers) contain none of the
# five characters that need escaping. `sub?` is a single native scan;
# skip the char-by-char chop/case/link rebuild entirely when it's a no-op.
(de ht:esc (S)
   (if (or (sub? "&" S) (sub? "<" S) (sub? ">" S) (sub? "\"" S) (sub? "'" S))
      (pack
         (make
            (for C (chop S)
               (link
                  (case C
                     ("&" "&amp;")
                     ("<" "&lt;")
                     (">" "&gt;")
                     ("\"" "&quot;")
                     ("'" "&#39;")
                     (T C) ) ) ) ) )
      S ) )

# Void elements don't get a closing tag
(setq ht:Void
   '("area" "base" "br" "col" "embed" "hr" "img" "input" "link" "meta" "source" "track" "wbr") )

(de ht:attrs (Att)
   (cond
      ((not Att) "")
      ((or (sym? Att) (str? Att))
         (pack " class=\"" (ht:esc Att) "\"") )
      (T
         (pack
            (make
               (for P Att
                  (when (cdr P)
                     (link " " (car P) "=\"" (ht:esc (cdr P)) "\"") ) ) ) ) ) ) )

(de ht:frag? (X)
   (and (pair X) (== (car X) 'ht:H)) )

# render one child: fragment -> unwrap, string/symbol -> escape, list -> recurse
(de ht:render (X)
   (cond
      ((ht:frag? X) (cdr X))
      ((or (str? X) (sym? X)) (ht:esc X))
      ((pair X) (apply pack (mapcar ht:render X)))
      ((not X) "")
      (T (ht:esc X)) ) )

# Unwrap a top-level fragment to its final HTML string
(de html (Frag)
   (if (ht:frag? Frag) (cdr Frag) Frag) )

# Wrap a literal string (e.g. containing an HTML entity like "&larr;") so it
# is spliced in verbatim instead of being escaped as plain text.
(de ht:ent (S)
   (cons 'ht:H S) )

# tag: build a tag-function for NAME, e.g. (ht:tag "div") defines <div>
(de ht:tag (Name)
   (let Sym (intern (pack "<" Name ">"))
      (def Sym
         (curry (Name) @
            (let Att (next)
               (cons 'ht:H
                  (pack
                     "<" Name (ht:attrs Att)
                     (if (member Name ht:Void)
                        "/>"
                        (pack ">"
                           (apply pack (mapcar ht:render (rest)))
                           "</" Name ">" ) ) ) ) ) ) )
      Sym ) )

(mapc ht:tag
   '("html" "head" "title" "meta" "link" "script" "style" "body"
      "header" "footer" "nav" "main" "section" "div" "span" "p"
      "h1" "h2" "h3" "h4" "a" "ul" "li" "table" "thead" "tbody" "tr" "th" "td"
      "form" "input" "button" "label" "select" "option" "textarea"
      "br" "hr" "img" "small" "strong" "em" ) )

# page: wraps a body fragment in a full HTML5 document, returns a fragment
(de ht:page (Title Page Body)
   (cons 'ht:H
      (pack
         "<!DOCTYPE html>"
         (html
            (<html> '(("lang" . "en"))
               (<head> NIL
                  (<meta> '(("charset" . "UTF-8")))
                  (<title> NIL (pack Title " - fixi demo"))
                  (<script> '(("src" . "/dist/the-fixi-project.js")) "")
                  (<link> '(("rel" . "stylesheet") ("href" . "/css/layout.css")))
                  (if Page
                     (<link> (list (cons "rel" "stylesheet") (cons "href" (pack "/css/" Page ".css"))))
                     "" ) )
               (<body> NIL
                  (<header> '(("class" . "nav"))
                     (<a> '(("href" . "/")) (ht:ent "&larr; demo index")) )
                  Body ) ) ) ) ) )
