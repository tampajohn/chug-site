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
fi

# 3. no lorem/placeholder/TODO strings
if [ -f index.html ] && grep -qiE 'lorem|ipsum|placeholder|TODO|FIXME|TBD' index.html; then
  fail "placeholder-like string found in index.html"
fi

# 4. hrefs: https://github.com/tampajohn/... or in-page #anchor that exists
# 5. python3 html.parser validation passes
python3 - <<'PY' || fail "html checks (hrefs / html.parser) failed"
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
    if h.startswith("#") and len(h) > 1 and c.ids.get(h[1:]):
        continue
    errs.append("bad href: %r" % h)
if errs:
    print("\n".join("  - " + e for e in errs))
    sys.exit(1)
print("  html.parser + hrefs: OK (%d hrefs, %d ids)" % (len(c.hrefs), len(c.ids)))
PY

if [ "$fails" -eq 0 ]; then
  echo "verify: OK - all checks green"
else
  echo "verify: $fails check(s) failed"
  exit 1
fi
