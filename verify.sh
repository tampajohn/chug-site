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
  #     those are cited git history, not rotting page stats. What remains is
  #     flagged when one line carries BOTH a digit and a metric claim word.
  bad=$(sed -n '/<body>/,/<\/body>/p' index.html \
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
              s/[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?Z?/ TIME /g' \
    | grep -iE '[0-9].*(tests?|items?|land(ed|ing|s)?|cycles?|green|lines|mutants?|rounds?|recoveries|iterations?|records?|queue)|(tests?|items?|land(ed|ing|s)?|cycles?|green|lines|mutants?|rounds?|recoveries|iterations?|records?|queue).*[0-9]')
  if [ -n "$bad" ]; then
    fail "hardcoded metric outside the STATS region (digit + claim word): $(echo "$bad" | head -2 | tr '\n' ' ' | cut -c1-200)"
  fi
fi

# 3. no lorem/placeholder/TODO strings — hand-written parts only: the
#    machine-written stats region between the STATS markers is regenerated
#    by chug's scripts/site-sync.sh and legitimately cites real repo files
#    (TODO.md, git refs); sweeping it would red-flag honest facts.
if [ -f index.html ]; then
  if awk '/^[[:space:]]*<!-- STATS:BEGIN -->[[:space:]]*$/{skip=1}
          !skip{print}
          /^[[:space:]]*<!-- STATS:END -->[[:space:]]*$/{skip=0}' index.html \
     | grep -qiE 'lorem|ipsum|placeholder|TODO|FIXME|TBD'; then
    fail "placeholder-like string found in index.html"
  fi
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
    if h == "https://videoamp.com":
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
