# LibraryX architecture

## Reference behavior

AlReaderX 2507171 is the behavioral reference for catalog navigation and
information density. LibraryX does not copy AlReaderX code. It reimplements the
observed/reverse-engineered behavior on top of KOReader APIs.

## Boundary

```text
LibraryX UI / query state
        |
libraryx.sqlite3
        |
KOReader metadata + sidecars + history
        |
KOReader ReaderUI
```

KOReader remains responsible for rendering and reading books.

## State model

A single versioned query/navigation state drives all catalog views. A navigation
frame carries at least:

- mode
- selected entity/context
- current search text
- filters
- sort + direction
- page / scroll position

Back restores the previous frame instead of reconstructing a new generic view.

Initial modes mirror the AlReaderX state machine semantically:

- start
- authors
- series
- titles
- books
- genres
- languages
- scan_dates
- file_dates
- filters
- folders
- formats
- recent
- random
- goto_author
- goto_series
- goto_folder

## Storage

LibraryX owns `libraryx.sqlite3`. It uses normalized entity/link tables instead
of reproducing AlReaderX's historical denormalized schema, but it preserves the
same query semantics and adds view-oriented indexes.

KOReader remains the authoritative source for reading progress/status and
last-read history. LibraryX mirrors those fields into its index for fast list
queries and refreshes them incrementally.

## E-ink constraints

- no animation dependency
- windowed/paginated SQL queries
- lazy cover loading
- background/chunked indexing
- preserve list position on return
- avoid whole-screen redraws when a row-level update is sufficient
