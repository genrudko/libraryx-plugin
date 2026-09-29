# LibraryX.koplugin

LibraryX is an indexed library frontend for KOReader, targeting an AlReaderX-like
navigation model and information density while leaving KOReader as the actual
reading engine.

## Status

**M0 — compatibility spike (in progress).**

The current build intentionally does *not* replace KOReader's home/file manager.
It adds `LibraryX → Compatibility probe` to the FileManager menu and verifies,
on the real device, that the KOReader build exposes the APIs LibraryX needs:

- `lua-ljsqlite3`
- writable KOReader settings storage
- metadata / cover extraction facade
- reading status and progress from `BookList`
- last-read history from `ReadHistory`
- `ReaderUI:showReader`
- document provider lookup

## Install the M0 probe

Copy this repository directory to:

```text
/mnt/us/koreader/plugins/libraryx.koplugin
```

Restart KOReader, open the FileManager menu and run:

```text
LibraryX → Compatibility probe
```

Send the displayed report if any probe fails.

## Design target

The product target is *not* a Bookshelf fork. It is a separate indexed catalog
with AlReaderX-style navigation:

- all books
- authors
- series
- titles
- folders
- genres / language / format / date filters
- recent and random
- contextual `Go to author / series / folder`
- persistent back-stack including list position, search, filter and sort state
- compact rows with cover, title, author, series index, metadata, last-read time
  and KOReader progress

See `docs/ARCHITECTURE.md`.
