# Changelog

## 0.1.0 — first release

- Browser front end for Dojuboga in a single self-contained page (`web/index.html`):
  SVG board, drag-and-drop or tap-to-place, rotate, pick up, hints, solution,
  keyboard play, phone layout, solved animation (respects reduced motion).
- Local mode: `serve()` runs a small standard-library web server on 127.0.0.1
  that generates puzzles on demand.
- Static mode: `export_site(dir)` writes the page plus puzzle packs for GitHub
  Pages or any static host; `serve(site = dir)` previews it.
- Puzzle JSON format `dojuboga-puzzle` version 1 (see README.md), `puzzle_json`.
