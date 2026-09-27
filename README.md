# The Fantasy Shelf

A small terminal book manager for a reader who enjoys all kinds of fantasy,
including *The Lord of the Rings*. Track books, look up metadata, and ask three
AI readers for different perspectives on your next read.

## Setup and run

Requirements: Bash 3.2+, Gum, jq, Python 3, and curl. Codex CLI is needed only
for AI recommendations. On macOS with Homebrew:

```bash
brew install gum jq python
# If Codex CLI is not already installed:
brew install --cask codex
codex login
```

Choose **Sign in with ChatGPT**. This project uses your included Codex allowance;
it does not set up API billing. It refuses API-key login and requests ChatGPT
access explicitly. Your account needs Codex access, internet connectivity, and
remaining usage allowance. The CLI's configured model is retained. Install a
recent CLI supporting `exec --ephemeral --output-schema --output-last-message`.
See [Codex CLI](https://learn.chatgpt.com/docs/codex/cli) and
[authentication](https://learn.chatgpt.com/docs/auth).

On Linux, install Gum from its [official instructions](https://github.com/charmbracelet/gum#installation),
plus Bash, jq, Python 3, curl, and Codex CLI using your distribution's supported
installation methods.

From this directory:

```bash
bash app.sh
# Separate temporary fantasy library; discarded when you exit:
bash app.sh --demo
```

Use arrow keys and Enter to select, Esc to go back, and Quit to exit. The real
library starts empty. Demo mode uses example books without changing your real
library, but its **AI recommendations are live and consume Codex allowance**.

The menu supports browsing, adding, searching, updating status/rating, and
getting recommendations. Adding a book offers metadata lookup or manual entry.
Review the details before saving. Search matches title, author, and genre.
Statuses are `want-to-read`, `reading`, and `finished`; ratings are optional 1–5.

## Architecture

`app.sh` checks dependencies and starts the Gum UI. The UI calls workflows,
which coordinate book and recommendation components. Only the data-layer
script opens the library CSV, using a small embedded Python CSV routine for
proper quoting and atomic writes. Components exchange JSON Lines on stdout;
progress and errors go to stderr. The application logic and orchestration stay
in Bash. Python also supplies a small process-group timeout helper and the
recommendation normalization routine, avoiding platform-specific shell tools.

```text
Gum UI → workflows → book/recommendation scripts → data layer → CSV
                      ├ history   ──┐
                      ├ interests ──┼→ combine | refine → UI → save
                      └ discovery ──┘
```

The recommendation workflow launches three scripts with `&`, captures their
process IDs using `$!`, and collects completion with `wait`. Each calls Codex
independently with a different prompt and a JSON output schema. Calls run in a
read-only sandbox with ephemeral sessions and temporary working directories.
Prompts ask for no tools or file operations. The current library and optional
session interest are sent to Codex as reader data; prompts exclude stored links.
A Python supervisor limits each call to 120 seconds and cleans up its process
group on timeout or cancellation. The workflow prints running/done/failed states
and elapsed time, then pipes successful results into refinement.

Refinement excludes saved books, deduplicates normalized title/author pairs, and
takes up to five books in history/interests/discovery round-robin order. This is
transparent balancing, not a claimed objective ranking. Unicode normalization,
case folding, and collapsed whitespace determine identity; different editions
or substantially different title/author spellings may need manual review.

## Personalization

The Fantasy Shelf defaults to a broad interest in fantasy and Tolkien's
*The Lord of the Rings*. History suggestions favor saved books and high ratings;
interest suggestions explore fantasy subgenres; discovery suggestions reach
into less familiar or adjacent genres. You can add a preference such as cozy
magic or epic journeys for each session. Suggestions include short spoiler-free
reasons. The interface uses a restrained purple fantasy theme. Sample demo
books are examples, not claims about your actual reading history.

## Failures and limitations

Library features work without Codex or internet access. Metadata comes from
[Open Library](https://openlibrary.org/dev/docs/api/search), with a 15-second
request timeout and manual entry when no usable result is available. Genre
suggestions are editable. AI suggestions can be inaccurate: review book details
and Open Library matches before saving; the AI is not asked to invent URLs.

If one AI strategy fails, successful results still appear. If all fail, the app
explains the failure and returns to its menus. There are no automatic AI retries
and no offline suggestion catalog. Last results remain in memory until exit;
browsing them again does not call Codex. Ctrl-C cancels active work (and may exit
the app); cleanup removes temporary data. Normal changes are saved immediately.

This is a local, single-user application: run only one writer against a library
at a time. The default CSV is part of the project, so review changes before
pushing personal reading data to GitHub. No login credentials belong in the repo.

## Component interfaces

Run components from any working directory. Set `BOOK_DB` to select a separate
CSV; otherwise it defaults to this project's `data/books.csv`.

```bash
bash data/book_database.sh list
bash data/book_database.sh search fantasy
printf '%s\n' '{"title":"The Hobbit","author":"J. R. R. Tolkien","genre":"Fantasy"}' \
  | bash data/book_database.sh add
printf '%s\n' '{"status":"finished","rating":"5"}' \
  | bash data/book_database.sh update 'The Hobbit' 'J. R. R. Tolkien'
bash data/book_database.sh exists 'The Hobbit' 'J. R. R. Tolkien'
echo fantasy | bash books/search_books.sh
bash books/fetch_book_metadata.sh 'The Hobbit' 'Tolkien'
bash workflows/get_recommendations.sh 'Dragons and epic journeys'
```

Book records use string fields `title,author,genre,status,rating,link`; omitted
optional fields are blank and a new book defaults to `want-to-read`. `add` and
`update` read one JSON object from stdin and return the saved record. `update`
accepts only status/rating. `list` and `search` return JSON Lines. `exists` returns
exit 0 if found and 1 if absent; invalid data or storage errors return 2.
Recommendation scripts read library JSON Lines from stdin, accept an optional
interest as argument 1, and return `title,author,genre,reason,strategy` JSON Lines.
`BOOK_AI_TIMEOUT` overrides the default 120 seconds for testing.

## Validation

```bash
# Optional: pip install pexpect (enables real Gum terminal tests)
python3 -m unittest discover -s tests -v
# Optional development tool: brew install shellcheck
shellcheck -x app.sh books/*.sh data/*.sh lib/*.sh ui/*.sh workflows/*.sh recommendations/*.sh
```

Tests use temporary libraries and fake Codex/curl executables. They cover CSV
round trips, input validation, duplicate detection, metadata failures, balanced
refinement, overlapping AI processes, partial/total failures, malformed output,
authentication, timeouts, cancellation, and paths with spaces. No paid calls are
made by the automated suite.

## Narrated demo — recording still required

The required narrated video has **not been recorded yet**. Follow the
[demo outline](docs/DEMO.md), then replace this paragraph with your actual video
link before submission. Original requirements are preserved in
[the assignment](docs/ASSIGNMENT.md).

Submit the repository URL in the class sheet under **Assignment No 2** after
adding your narrated demo.
