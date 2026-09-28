# SITE-SPEC — chug marketing site (built by chug itself)

You are building the public marketing site for chug, the autonomous coding
harness that is building you right now. Static site, no build step, GitHub
Pages served from main root.

check: bash verify.sh

## Hard rules

- **Facts only from the source repo** at ~/workspace/chug (READ-ONLY):
  README.md, FEATURES.md, TODO.md, EVALUATION.md, LOOP-SPEC.md. Quote real
  numbers (TODO items landed, test counts, cycle arcs) — verify each
  against the source; NEVER invent metrics or capabilities.
- **No external assets**: no CDNs, no webfonts, no images from the network.
  System font stack + inline SVG only. No frameworks, no build tools —
  hand-written HTML/CSS, minimal JS only if it earns its place.
- **Design**: dark terminal aesthetic (bg ~#0d1117, mono for code/numbers,
  one accent color), readable, fast, mobile-sane. Think "a README that
  became a beautiful page", not a SaaS template.
- Commit per section; push to main when done (gh is authed).

## Required sections (single index.html, verify.sh checks these)

1. **Hero**: name + one-line promise ("Autonomous coding harness — given a
   spec and a goal, it keeps on chugging") + the loop-is-code tagline +
   repo link.
2. **How it works**: the loop as a visual (styled HTML/CSS diagram, inline
   SVG if useful): spec+goal in → driver loop → tools → verified
   goal_complete; LEDGER.md as external memory.
3. **Proof it runs itself**: the self-improvement story — real numbers from
   TODO.md/EVALUATION.md (items landed T1-current, validation sagas like
   the 5-round tgrep arc, the dogfood facts: it wrote its own chat mode,
   its own delegate tool, and this very site).
4. **Feature grid**: tools, delegate sub-agents, plan mode, hooks,
   permissions, risk-gate (Laya), MCP, Langfuse observability, TUI,
   web_fetch, tgrep — from FEATURES.md/README only.
5. **The loop doctrine**: evaluate → queue → implement (glm) → adversarial
   validation (kimi, mutation testing) → merge → push — one honest
   paragraph + the LOOP-SPEC.md link.
6. **Get started**: the real quickstart from README (clone, build, run
   LOOP-SPEC) — copy the commands verbatim, they must work.

## verify.sh (write it first, keep it green)

- index.html exists and is < 200KB (plus optional style.css < 50KB)
- all 6 section markers present (grep stable ids)
- no lorem/placeholder/TODO strings
- every href is https://github.com/tampajohn/ or an in-page #anchor that
  exists in the document
- python3 -c html.parser validation passes


## Living-site rules (added 2026-09-28 after stats-sync went live)

- **No hardcoded numbers outside the STATS:BEGIN/END region.** Any metric
  on the page (items landed, tests, cycles, dates) exists ONLY inside the
  synced region — hero and prose sections stay qualitative ("keeps on
  chugging", "adversarial validation") or link to #stats. The
  sync script owns all numbers; anything else rots (header went stale
  within a day of launch).
- **Every section is navigable.** Each top-level section has a stable id
  and an entry in the page nav (stats/timeline/features/doctrine/get-
  started all reachable). verify.sh checks: every section id appears in a
  nav href, and no absolute metric outside the STATS region (grep for
  digits-adjacent-to-claims pattern).

## Out of scope

- Analytics, comments, forms, anything backend. Blog posts. Docs mirrors.
