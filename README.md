# Notes — Windows-style notes app with diagram drawing

A Flutter desktop app inspired by the Windows Sticky Notes / Fluent design:
a sidebar list of colored notes with search, pinning and instant autosave —
plus a **Draw mode** on every note for sketching diagrams.

![platform](https://img.shields.io/badge/platform-Windows-blue)

## Features

### Notes (like Windows Sticky Notes)
- Colored notes (8-color palette) with a tinted editor surface per note
- **Rich text**: bold, italic, underline, strikethrough — select text and use
  the toolbar or `Ctrl+B` / `Ctrl+I` / `Ctrl+U`; formatting is saved.
  Toolbar buttons keep the caret in the editor
- **Checklists**: toolbar button cycles selected lines plain → ☐ → ☒ → plain;
  bullets convert to checkboxes. Pressing Enter continues the list (or exits
  it on an empty item); Enter after a checked item starts an unchecked one
- **Bulleted & numbered lists**: one-click toggle between plain text and
  `- ` bullets or `1. ` numbers (other list markers convert along the
  way). Enter continues any list — numbered items increment — and an
  empty item exits it. Numbered runs renumber themselves automatically
  after edits (delete an entry and the rest shift up)
- **Headings**: `H1` / `H2` chips in the formatting bar
- **Tables (Excel-style)**: the toolbar button inserts a spreadsheet-like
  grid right inside the note — column letters (A, B, C…), a row-number
  gutter, crisp gridlines, a shaded bold header row, and a green
  active-cell border with fill handle. Pick a size from the grid picker or
  type exact columns/rows. Editing works like Excel: click a cell to
  select it, type to replace its content, double-click / `Enter` / `F2`
  to edit in place, `Enter` commits and moves down, `Tab` / `Shift+Tab`
  move along the row, arrows move the selection, `Delete` clears a cell,
  `Ctrl+C` / `Ctrl+V` copy and paste it. Right-click a cell, column letter
  or row number for insert row above/below, insert column left/right,
  clear contents, delete row/column/table; the toolbar's Table menu (and
  the ＋ row / ＋ column helpers that appear under the grid) offer the
  same operations. Tables are stored as plain Markdown pipe tables, so
  `.txt` exports stay portable — and pasting or typing a Markdown table
  converts it into a grid
- **Insert date & time** at the caret from the formatting bar
- Word/character count, search (matches note text *and* diagram labels),
  light/dark/system theme
- Sidebar list with previews, live diagram thumbnails, pin, duplicate,
  delete (right-click a card for the context menu); **resizable** — drag
  the divider between the list and the editor (width is remembered)
- **Export**: note as `.txt`, diagram as `.png` (2× resolution) — saved to
  your Downloads folder via the ⋯ menu in the editor top bar
- Autosave to a local JSON file (debounced; flushed on minimize/exit).
  Saves are atomic and keep a `.bak` copy that is auto-recovered if the
  main file is ever corrupt
- Keyboard: `Ctrl+N` new note, `Ctrl+F` search, `?` button shows all
  shortcuts

### Draw mode (per-note diagram canvas, Excalidraw-style)
- **Sketchy rendering**: shapes draw as wobbly hand-drawn outlines (stable
  per stroke), with hachure / solid / cross-hatch fills and solid / dashed
  / dotted outlines
- **Shapes**: line, rectangle, ellipse, diamond, arrow — hold `Shift` to
  snap lines/arrows to 45° and force squares/circles/regular diamonds
- **Style applies to selection**: pick ink, width, fill or stroke style
  while a shape is selected to restyle it (with undo)
- **Select & move**: click a stroke to select it, drag to move; drag on
  empty canvas to rubber-band **multi-select** (or `Shift`+click to add
  and remove), then move, restyle, duplicate or delete them together;
  arrow keys nudge (`Shift` = 10 px), `Delete` removes, `Ctrl+D`
  duplicates, `Esc` deselects
- **Resize & rotate**: a single selection shows Excalidraw-style handles —
  drag corners/edges to resize (`Shift` keeps the aspect ratio; stroke
  width and text size scale along) and the round handle above the box to
  rotate (`Shift` snaps to 15°)
- **Right-click a stroke** for a context menu: edit label, duplicate,
  bring to front / send to back, delete
- **Layout like Excalidraw**: a vertical tool palette floating on the
  canvas' left edge (active tool highlighted) and a properties/actions bar
  along the bottom (undo/redo, selection actions, style pickers, zoom)
- **Text labels typed in place**: double-click empty canvas (or use the
  text tool) and type directly on the canvas — `Enter` for new lines,
  `Esc` or a click elsewhere commits (empty text discards). Labels use a
  handwritten font; pick their size from the bottom bar
- Pen, highlighter, stroke eraser (also erases with a stylus-eraser)
- 10 ink colors, 5 stroke widths
- Undo/redo (`Ctrl+Z` / `Ctrl+Y` or `Ctrl+Shift+Z`, up to 200 steps,
  covers moves, z-order changes and erases), clear canvas
- Duplicate / delete buttons for the current selection, grid on/off,
  zoom-to-fit
- Pan (hand tool, middle-mouse drag or trackpad), zoom (mouse wheel,
  buttons or trackpad pinch) with a clickable zoom percentage in the
  bottom bar, reset view

## Run

```sh
flutter pub get
flutter run -d windows
```

## Build a release executable

```sh
flutter build windows --release
```

The exe lands in `build\windows\x64\runner\Release\notes_app.exe`.

## Testing

```sh
flutter test
```

Covers note/stroke/format JSON round-trips, rich-text span adjustment
across edits, smart list continuation, checklist/bullet cycling, composing
rendering, and store save/backup/recovery.

## Features (v2)

### Organization
- Tags (`#tag` inline + explicit tag editor), tag filter chips + counts
- Favorites (★) separate from pins; Archived; Trash with restore,
  delete-forever and 30-day auto-purge + empty-trash
- Sort: updated / created / title / color; color filter; full-text search
  across body, tags and diagram labels with match highlighting
- Views: All / Favorites / Due / Archived / Trash

### Editor
- Code + quote formatting, links, dividers
- Note templates (meeting, todo, project plan, blank table)
- Version history (30 snapshots) with restore
- Reminders / due dates with due strip + in-app due notifications
- PIN lock per note (UI lock) with unlock card
- Word goals + writing stats, checklist progress bars
- Attachments (name + path) per note
- Export: `.txt`, `.md`, printable `.html` (→ PDF via browser),
  tables `.csv`, diagram `.png` / `.svg`, copy SVG to clipboard

### Draw mode
- Canvas sticky notes (drag to size, double-click to edit text)
- Laser pointer (temporary red trail, never saved)
- Snap-to-grid toggle, shape locking (select-only, skip erase/move),
  layers panel (reorder, lock, jump-to)
- Sticky + lock persist in JSON; SVG export covers all stroke types

### Data & polish
- Daily timestamped backups (last 7) + one-click restore point via
  `backups/`; best-effort mirror into OneDrive/Dropbox folder
- Accent color override + compact density; `Ctrl+Shift+F` global search
  focus, `Ctrl+K` quick capture; calendar/reminders dialog
- All new fields are backward compatible — old `notes.json` files load
  with defaults.

## Project structure

```
lib/
├── main.dart                     # app entry + theming (accent, density)
├── controllers/
│   ├── notes_controller.dart     # state: notes, views, tags, reminders, lock
│   └── format_text_controller.dart # rich-text field + lists + rendering
├── models/
│   ├── note.dart                 # note model + history + attachments
│   ├── stroke_item.dart          # canvas item (+ sticky, locked)
│   └── format_span.dart          # rich-text ranges + edit remapping
├── services/
│   └── notes_store.dart          # atomic JSON + .bak + daily backups + mirror
├── theme/
│   └── note_palette.dart         # Sticky-Notes-style color palette
├── utils/
│   ├── format.dart               # date labels
│   ├── markdown_table.dart       # Notepad-style pipe-table model + edits
│   ├── note_templates.dart       # built-in templates
│   └── export.dart               # .txt/.md/.html/.csv/.png/.svg exports
├── pages/
│   └── home_page.dart            # two-pane layout + shortcuts + due strip
└── widgets/
    ├── sidebar.dart              # views, search, tags, sort, calendar
    ├── note_card.dart            # card + badges + progress + highlight
    ├── editor_pane.dart          # top bar, lock, history, tags, goals, files
    └── drawing/
        ├── diagram_canvas.dart   # canvas (+ sticky, laser, snap, lock, layers)
        ├── diagram_toolbar.dart  # tool palette (+ sticky, laser)
        ├── diagram_painter.dart  # grid + strokes painter, thumbnails
        └── stroke_render.dart    # shared painting + hit-testing (+ sticky)
```
