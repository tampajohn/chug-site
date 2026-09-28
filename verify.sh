#!/usr/bin/env bash
# verify.sh - SITE-SPEC compliance checks for the chug marketing site.
# Run: bash verify.sh   (exit 0 = green)
set -u
cd "$(dirname "$0")"
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

# 1. index.html exists and is < 200KB (optional style.css < 50KB)
if [ ! -f index.html ]; then
  fail "index.html is missing"
else
  b=$(wc -c < index.html | tr -d ' ')
  [ "$b" -lt 204800 ] || fail "index.html is $b bytes (must be < 200KB)"
fi
if [ -f style.css ]; then
  b=$(wc -c < style.css | tr -d ' ')
  [ "$b" -lt 51200 ] || fail "style.css is $b bytes (must be < 50KB)"
fi

# 2. all 6 section markers present (stable ids)
if [ -f index.html ]; then
  for id in hero how-it-works proof timeline features doctrine get-started; do
    grep -q "id=\"$id\"" index.html || fail "missing section marker id=\"$id\""
  done
  # 2b. timeline section: rail + at least 12 dated entries
  n=$(grep -c 'class="tl-item' index.html)
  [ "$n" -ge 12 ] || fail "timeline has $n entries (need >= 12)"
  grep -q 'class="tl"' index.html || fail "timeline rail (.tl) missing"

  # 2c. stats sync region: scripts/site-sync.sh (tampajohn/chug T98) rewrites
  #     ONLY between the markers, so the page must carry exactly one
  #     BEGIN/END pair (same line grammar the sync script greps for), inside
  #     <body>, positioned after the proof section and before the timeline.
  nb=$(grep -cE '^[[:space:]]*<!-- STATS:BEGIN -->[[:space:]]*$' index.html)
  ne=$(grep -cE '^[[:space:]]*<!-- STATS:END -->[[:space:]]*$' index.html)
  bl=$(grep -nE '^[[:space:]]*<!-- STATS:BEGIN -->[[:space:]]*$' index.html | head -1 | cut -d: -f1)
  el=$(grep -nE '^[[:space:]]*<!-- STATS:END -->[[:space:]]*$' index.html | head -1 | cut -d: -f1)
  if [ "$nb" -ne 1 ] || [ "$ne" -ne 1 ] || [ -z "$bl" ] || [ -z "$el" ] || [ "$bl" -ge "$el" ]; then
    fail "stats markers malformed: BEGIN x$nb (line ${bl:-none}), END x$ne (line ${el:-none}) — need exactly one of each, BEGIN before END"
  else
    body=$(grep -n '<body>' index.html | head -1 | cut -d: -f1)
    endbody=$(grep -n '</body>' index.html | head -1 | cut -d: -f1)
    proof=$(grep -n 'id="proof"' index.html | head -1 | cut -d: -f1)
    tline=$(grep -n 'id="timeline"' index.html | head -1 | cut -d: -f1)
    if [ -z "$body" ] || [ -z "$endbody" ] || [ "$bl" -le "$body" ] || [ "$el" -ge "$endbody" ]; then
      fail "stats region not inside <body> (BEGIN line $bl, END line $el, body ${body:-?}..${endbody:-?})"
    elif [ "$bl" -le "$proof" ] || [ "$el" -ge "$tline" ]; then
      fail "stats region not between the proof and timeline sections (BEGIN line $bl, END line $el, proof $proof, timeline $tline)"
    fi
  fi

  # 2d. Living-site rule: every top-level section id appears in a nav href
  for id in hero how-it-works proof stats timeline features doctrine get-started; do
    grep -q "id=\"$id\"" index.html || fail "missing section marker id=\"$id\""
    grep -q "href=\"#$id\"" index.html || fail "section id=\"$id\" is not navigable (no href=\"#$id\" anywhere)"
  done

  # 2e. Living-site rule: no hardcoded metrics outside the STATS:BEGIN/END region.
  #     Grep heuristic, not a parser: body-only, skip the machine-synced STATS
  #     region, verbatim <pre> command samples, the hero terminal sketch, and
  #     HTML comments; strip tags; strip identifier-like tokens (queue T-ids,
  #     validation R-labels, SPEC-N, 7+ char hex hashes, dates, clock times) —
  #     those are cited git history, not rotting page stats. Two greps run over
  #     the one masked stream:
  #       (a) same-line: a digit and a metric claim word share a line
  #           (catches inline prose like "721 tests green");
  #       (b) cross-line adjacency: in the line-joined stream a digit and a
  #           count unit sit within two short words of each other, either
  #           direction, with an optional :/= separator — this is the
  #           literal-digit-chip hole: chip/card markup routinely puts the
  #           number and its label on separate source lines
  #           (<span class="chip"><b>721</b></span> / "tests green"), which
  #           (a) cannot see. Periods/other punctuation break the window, so
  #           ordinary sentences stay clear.
  #     Code blocks stay exempt: <pre> lines are dropped above, so commands
  #     with flags/versions (--max-iters 40, cargo test) never reach either
  #     grep; the synced STATS region is the one home of real numbers.
  masked=$(sed -n '/<body>/,/<\/body>/p' index.html \
    | awk '
        /^[[:space:]]*<!-- STATS:BEGIN -->[[:space:]]*$/{instats=1; next}
        /^[[:space:]]*<!-- STATS:END -->[[:space:]]*$/{instats=0; next}
        instats{next}
        /<pre/{inpre=1}
        inpre{if(/<\/pre>/) inpre=0; next}
        /class="term-body"/{interm=1}
        interm{if(/class="term-cap"/) interm=0; next}
        /<!--/{next}
        {print}' \
    | sed -E 's/<[^>]*>/ /g;
              s/T[0-9]+/ ID /g;
              s/R[0-9]+/ ID /g;
              s/SPEC-[0-9]+/ ID /g;
              s/v[0-9][0-9a-z.]*/ VER /g;
              s/glm-[0-9][0-9a-z.-]*/ MODEL /g;
              s/kimi-k[0-9][0-9a-z-]*/ MODEL /g;
              s/[0-9a-f]{7,}/ HASH /g;
              s/20[0-9]{2}-[0-9]{2}-[0-9]{2}/ DATE /g;
              s/[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?Z?/ TIME /g')
  units='tests?|items?|land(ed|ing|s)?|cycles?|green|lines|mutants?|rounds?|recoveries|iterations?|records?|commits?|tools?|queue'
  bad=$(printf '%s\n' "$masked" \
    | grep -iE "[0-9].*($units)|($units).*[0-9]")
  if [ -n "$bad" ]; then
    fail "hardcoded metric outside the STATS region (digit + claim word on one line): $(echo "$bad" | head -2 | tr '\n' ' ' | cut -c1-200)"
  fi
  bad=$(printf '%s' "$masked" | tr '\n' ' ' \
    | grep -ioE "[0-9][0-9.,/%x]*([ ]+[a-z-]{1,20}){0,2}[ ]+($units)\b|\b($units)([ ]+[a-z-]{1,20}){0,2}([ ]*[:=][ ]*|[ ]+)[0-9]")
  if [ -n "$bad" ]; then
    fail "hardcoded metric outside the STATS region (digit chip adjacent to its unit across markup/lines): $(echo "$bad" | head -2 | tr '\n' ' ' | cut -c1-200)"
  fi
fi

# 3. no lorem/placeholder/TODO strings — hand-written parts only: the
#    machine-written STATS, TIMELINE, and FEATURES regions are regenerated by
#    chug's scripts/site-sync.sh (T98/T99) and legitimately cite real repo
#    artifacts (TODO.md rows, tool names like todo_add, F-item titles like
#    "Structured todo tool"); sweeping them would red-flag honest facts.
if [ -f index.html ]; then
  if awk '
      /<!-- (STATS|TIMELINE|FEATURES):BEGIN -->/{skip=1; next}
      /<!-- (STATS|TIMELINE|FEATURES):END -->/{skip=0; next}
      skip{next}
      {print}' index.html \
     | grep -qiE 'lorem|ipsum|placeholder|TODO|FIXME|TBD'; then
    fail "placeholder-like string found in index.html"
  fi
fi

# 3b. social meta pack + local assets: the og card must be referenced by its
#     ABSOLUTE https://chug.sh URL (Slack/Twitter fetch it after deploy) while
#     every referenced file exists on disk (living-site rule: local assets
#     only). og.png dims are read from the PNG IHDR header — the gate does
#     not need Pillow.
if [ -f index.html ]; then
python3 - <<'PY' || fail "meta pack / asset checks failed"
import os, re, struct, sys
import xml.etree.ElementTree as ET

src = open("index.html", encoding="utf-8").read()
head = src.split("</head>")[0]
errs = []

def tag(attr, key):
    m = re.search(r"<(?:meta|link)\b[^>]*\b%s=[\"']%s[\"'][^>]*>" % (attr, re.escape(key)), head)
    if not m:
        return None
    t = m.group(0)
    for a in ("content", "href"):
        c = re.search(r'\b%s=["\']([^"\']*)["\']' % a, t)
        if c:
            return c.group(1)
    return ""

def want(kind, key, val, label, nonempty_ok=False):
    got = tag(kind, key)
    if got is None:
        errs.append("missing %s" % label)
    elif nonempty_ok and not got.strip():
        errs.append("%s is empty" % label)
    elif not nonempty_ok and got != val:
        errs.append("%s: got %r, want %r" % (label, got, val))

want("name", "description", None, "meta description", nonempty_ok=True)
want("property", "og:title", None, "og:title", nonempty_ok=True)
want("property", "og:description", None, "og:description", nonempty_ok=True)
want("property", "og:type", "website", "og:type=website")
want("property", "og:url", "https://chug.sh/", "og:url")
want("property", "og:image", "https://chug.sh/assets/og.png", "og:image (absolute chug.sh URL)")
want("property", "og:image:width", "1200", "og:image:width")
want("property", "og:image:height", "630", "og:image:height")
want("property", "og:image:alt", None, "og:image:alt", nonempty_ok=True)
want("name", "twitter:card", "summary_large_image", "twitter:card=summary_large_image")
want("name", "twitter:title", None, "twitter:title", nonempty_ok=True)
want("name", "twitter:description", None, "twitter:description", nonempty_ok=True)
want("name", "twitter:image", "https://chug.sh/assets/og.png", "twitter:image")
want("rel", "canonical", "https://chug.sh/", "canonical link")
want("name", "theme-color", "#0d1117", "theme-color matching bg")
want("rel", "icon", "/assets/favicon.svg", "svg favicon link")
want("rel", "apple-touch-icon", "/assets/apple-touch-icon.png", "apple-touch-icon link")

def png_size(path):
    with open(path, "rb") as f:
        sig = f.read(8)
        if sig != b"\x89PNG\r\n\x1a\n":
            raise ValueError("%s: not a PNG" % path)
        f.read(8)  # IHDR length + chunk type
        w, h = struct.unpack(">II", f.read(8))
        return w, h

for p in ("assets/og.png", "assets/favicon.svg", "assets/apple-touch-icon.png"):
    if not os.path.isfile(p):
        errs.append("referenced asset missing on disk: %s" % p)

if os.path.isfile("assets/og.png"):
    try:
        w, h = png_size("assets/og.png")
        if (w, h) != (1200, 630):
            errs.append("assets/og.png is %dx%d, must be exactly 1200x630" % (w, h))
    except ValueError as e:
        errs.append(str(e))
if os.path.isfile("assets/apple-touch-icon.png"):
    try:
        w, h = png_size("assets/apple-touch-icon.png")
        if (w, h) != (180, 180):
            errs.append("assets/apple-touch-icon.png is %dx%d, must be 180x180" % (w, h))
    except ValueError as e:
        errs.append(str(e))
if os.path.isfile("assets/favicon.svg"):
    try:
        root = ET.parse("assets/favicon.svg").getroot()
        if root.tag.rsplit("}", 1)[-1] != "svg":
            errs.append("assets/favicon.svg: root element is not <svg>")
    except ET.ParseError as e:
        errs.append("assets/favicon.svg is not valid XML: %s" % e)
    body = open("assets/favicon.svg", encoding="utf-8").read()
    body_check = body.replace("http://www.w3.org/2000/svg", "")
    if "http://" in body_check or "https://" in body_check:
        errs.append("assets/favicon.svg contains an external URL (assets must be local)")

if errs:
    print("\n".join("  - " + e for e in errs))
    sys.exit(1)
print("  meta pack + assets: OK (og.png 1200x630, favicon.svg, apple-touch-icon 180x180)")
PY
fi
# 4. install one-liner block (tampajohn/chug T100): the get-started section
#    shows `curl -fsSL https://chug.sh/install.sh | sh`, links the script for
#    reading-before-piping, and the script itself is served from the repo root
#    (POSIX-syntax-clean). If any leg rots the one-liner lies — fail loud.
if [ -f index.html ]; then
  grep -qF 'curl -fsSL https://chug.sh/install.sh | sh' index.html \
    || fail "get-started install one-liner missing or changed (expect: curl -fsSL https://chug.sh/install.sh | sh)"
  grep -qF 'href="/install.sh"' index.html \
    || fail "get-started block does not link the script (href=\"/install.sh\")"
fi
if [ ! -f install.sh ]; then
  fail "install.sh missing at the site root (https://chug.sh/install.sh must serve)"
else
  sh -n install.sh || fail "install.sh fails sh -n syntax check"
fi

# 5. python3 html.parser validation passes
python3 - <<'PY' || fail "html checks (hrefs / html.parser) failed"
import os
import sys
from html.parser import HTMLParser

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr"}
errs = []

class Checker(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack, self.ids, self.idcount, self.hrefs = [], {}, {}, []
    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        if "id" in d:
            self.ids[d["id"]] = self.ids.get(d["id"], 0) + 1
        if "href" in d:
            self.hrefs.append(d["href"])
        if tag not in VOID:
            self.stack.append(tag)
    def handle_endtag(self, tag):
        if tag in VOID:
            return
        if self.stack and self.stack[-1] == tag:
            self.stack.pop()
        elif tag in self.stack:
            while self.stack and self.stack.pop() != tag:
                pass
            errs.append("mismatched close </%s>" % tag)
        else:
            errs.append("stray close </%s>" % tag)

src = open("index.html", encoding="utf-8").read()
c = Checker()
c.feed(src)
c.close()
if c.stack:
    errs.append("unclosed tags: %s" % ", ".join(c.stack))
for i, n in sorted(c.ids.items()):
    if n > 1:
        errs.append("duplicate id: %s (x%d)" % (i, n))
for h in c.hrefs:
    if h.startswith("https://github.com/tampajohn/"):
        continue
    if h == "https://videoamp.com":
        continue
    if h == "https://chug.sh/" or h.startswith("https://chug.sh/"):
        continue  # canonical site origin (og/canonical targets)
    if h == "/install.sh":
        if os.path.isfile("install.sh"):
            continue
        errs.append("href /install.sh but install.sh missing on disk")
    if h == "/llms.txt":
        if os.path.isfile("llms.txt"):
            continue
        errs.append("href /llms.txt but llms.txt missing on disk")
    if h.startswith("/assets/"):
        if os.path.isfile(h.lstrip("/")):
            continue
        errs.append("asset href points at a missing file: %r" % h)
    if h.startswith("#") and len(h) > 1 and c.ids.get(h[1:]):
        continue
    errs.append("bad href: %r" % h)
if errs:
    print("\n".join("  - " + e for e in errs))
    sys.exit(1)
print("  html.parser + hrefs: OK (%d hrefs, %d ids)" % (len(c.hrefs), len(c.ids)))
PY

# 6. llms.txt (llmstxt.org convention): exists at the repo root, parses as
#    markdown, links are https and resolve structurally — github.com blob
#    links must name real files in the source checkout (when present), chug.sh
#    anchor links must match ids in index.html. index.html must advertise it
#    (head alternate link) and mention it in the footer link row.
if [ ! -f llms.txt ]; then
  fail "llms.txt is missing"
else
  b=$(wc -c < llms.txt | tr -d ' ')
  [ "$b" -lt 51200 ] || fail "llms.txt is $b bytes (must be < 50KB — a curated map, not a docs mirror)"
  first=$(grep -m1 -v '^[[:space:]]*$' llms.txt)
  [ "$first" = "# chug" ] || fail "llms.txt must open with the H1 '# chug' (got: $first)"
  for sec in Docs Site Install; do
    grep -q "^## $sec\$" llms.txt || fail "llms.txt missing '## $sec' section"
  done
  grep -q '^> ' llms.txt || fail "llms.txt missing the blockquote summary (llmstxt.org convention)"
  if [ -f index.html ]; then
    grep -q '<link rel="alternate" type="text/plain" href="/llms.txt">' index.html \
      || fail "index.html head is missing the llms.txt alternate link"
    grep -q 'href="/llms.txt">llms.txt</a>' index.html \
      || fail "index.html footer link row is missing the llms.txt mention"
  fi
  SRC="${CHUG_SRC:-$HOME/workspace/chug}"
  python3 - "$SRC" <<'PY' || fail "llms.txt checks (markdown / links) failed"
import os, re, sys

text = open("llms.txt", encoding="utf-8").read()
src_root = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/workspace/chug")
html = open("index.html", encoding="utf-8").read() if os.path.isfile("index.html") else ""
lines = text.splitlines()
errs = []

# Structural markdown parse: balanced fences, one H1, required H2s, no HTML.
fence, in_fence, outside = 0, False, []
for i, line in enumerate(lines, 1):
    if line.strip().startswith("```"):
        fence += 1
        in_fence = not in_fence
        continue
    if not in_fence:
        outside.append((i, line))
if in_fence:
    errs.append("unbalanced code fence (odd ``` count: %d)" % fence)
h1 = [l for _, l in outside if re.match(r"#( |$)", l)]
h2 = [l for _, l in outside if re.match(r"##( |$)", l)]
if len(h1) != 1 or h1[0].strip() != "# chug":
    errs.append("expected exactly one H1 '# chug', got %r" % h1)
for want in ("## Docs", "## Site", "## Install"):
    if want not in h2:
        errs.append("missing required section %r" % want)
if not any(l.startswith(">") for _, l in outside):
    errs.append("missing blockquote summary after the H1 (llmstxt.org convention)")
for i, line in outside:
    if re.match(r"#+[A-Za-z]", line):
        errs.append("line %d: heading without a space after #:" % i)
    # inline code spans are literal text (e.g. `check: <shell command>`,
    # README's placeholder syntax) — strip them before the HTML scan
    if re.search(r"<[a-zA-Z/][^>]*>", re.sub(r"`[^`]*`", "", line)):
        errs.append("line %d: HTML in llms.txt (plain markdown only)" % i)
    if re.match(r"\[[^]]*\]\(\s*$", line) or ("](" in line and not re.search(r"\]\([^)\s]+\)", line)):
        errs.append("line %d: malformed markdown link" % i)
if not re.search(r"^## ", text, re.M) or "](https" not in text:
    errs.append("llms.txt has no linked sections (curated map must link out)")

# Link extraction + https/allowlist + structural resolution.
link_re = re.compile(r"\[[^\]]+\]\(([^)\s]+)\)")
links = [(i, m.group(1)) for i, line in outside for m in link_re.finditer(line)]
if not links:
    errs.append("no markdown links found")
ids = set(re.findall(r'id="([a-zA-Z0-9_-]+)"', html))
src_avail = os.path.isdir(src_root)
for i, url in links:
    if not url.startswith("https://"):
        errs.append("line %d: non-https link %r" % (i, url))
        continue
    host, _, path = url[len("https://"):].partition("/")
    if host == "github.com" and path.startswith("tampajohn/chug"):
        path = "/" + path
        m = re.match(r"^/tampajohn/chug/(?:blob|tree)/main/(.+)$", path)
        if m:
            rel = m.group(1).rstrip("/")
            if src_avail:
                if not os.path.isfile(os.path.join(src_root, rel)):
                    errs.append("line %d: %r does not exist in the source checkout %s" % (i, rel, src_root))
            elif "/" in rel:
                errs.append("line %d: nested path %r (no source checkout at %s to verify)" % (i, rel, src_root))
    elif host == "chug.sh":
        anchor = path.split("#", 1)[1] if "#" in path else ""
        if anchor:
            if anchor not in ids:
                errs.append("line %d: chug.sh anchor #%s has no matching id in index.html" % (i, anchor))
        elif path not in ("", "/"):
            errs.append("line %d: chug.sh path %r is not served by this single-page site" % (i, path))
    else:
        errs.append("line %d: link outside the allowed hosts (github.com/tampajohn/chug, chug.sh): %r" % (i, url))

if errs:
    print("\n".join("  - " + e for e in errs))
    sys.exit(1)
print("  llms.txt: OK (%d bytes, %d sections, %d links all https + structurally resolved%s)" % (
    len(text.encode()), len(h2), len(links), "; source checkout verified" if src_avail else ""))
PY
fi

if [ "$fails" -eq 0 ]; then
  echo "verify: OK - all checks green"
else
  echo "verify: $fails check(s) failed"
  exit 1
fi
