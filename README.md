# disk-cleanup-ruby

Ruby script to reclaim disk space on macOS by removing regenerable caches, Docker Desktop data, project build artifacts, trash contents, and installer/archive files from `Downloads`.

## What It Cleans

- `trash`: empty `~/.Trash`
- `downloads`: remove `*.dmg`, `*.zip`, `*.pkg`, `*.iso` from `~/Downloads`
- `caches`: remove `~/.npm/_cacache`, `~/.npm/_npx`, `~/.cache`, `~/.bun/install/cache`, `~/.cargo/registry`, `~/.nvm/.cache`, `~/.rustup/downloads`, `~/.rustup/tmp`, `~/.rvm/archives`, `~/.rvm/src`, `~/.rvm/tmp`, `~/.rvm/log`, `~/Library/pnpm/store`, and writable children under `~/Library/Caches` except Apple system caches (`com.apple.*`, CloudKit, Safari, and similar)
- `homebrew`: remove `~/Library/Caches/Homebrew/downloads`
- `docker`: remove Docker Desktop local data directories and `~/.colima`
- `claude`: remove `~/Library/Application Support/Claude/{vm_bundles,Cache,claude-code-vm}`
- `cursor`: remove Cursor's local history snapshots (`~/Library/Application Support/Cursor/snapshots`)
- `agents`: remove Codex and Grok session history and caches (`~/.codex/{sessions,archived_sessions}`, `~/.grok/{sessions,downloads,marketplace-cache}`)
- `worktrees`: remove git worktrees under `~/.config/superpowers/worktrees` that have no uncommitted changes and no commits ahead of their upstream
- `projects`: recursively remove regenerable directories like `node_modules`, `.next`, `.next-dev`, `.next-dev-*`, `dist`, `build`, `.turbo`, `.cache`, `coverage`, `output_directory`, `tmp`, `.zig-cache`, `.elixir_ls`, `_build`, `deps`, `.netlify`, `.pytest_cache`, `.venv`, and `venv` under `~/Desktop/Projetos`

## Usage

```bash
ruby disk_cleanup.rb --dry-run
ruby disk_cleanup.rb
ruby disk_cleanup.rb --map
ruby disk_cleanup.rb --map --top=5
ruby disk_cleanup.rb --map-path="$HOME/Library/Application Support/Claude" --top=20
ruby disk_cleanup.rb --only=claude
ruby disk_cleanup.rb --only=cursor
ruby disk_cleanup.rb --only=agents
ruby disk_cleanup.rb --only=downloads,caches,homebrew
ruby disk_cleanup.rb --skip=docker
ruby disk_cleanup.rb --min-age-days=7
ruby disk_cleanup.rb --force
```

## Disk Usage Mapping

Use `--map` to inspect the largest directories without deleting anything. The report shows:

- top directories in `HOME`, excluding `Library` and the configured projects root to avoid duplication
- top directories in the projects root
- top directories in `~/Library/Application Support`

Use `--top=N` to control how many rows each section prints.

Use `--map-path=PATH` to inspect one specific directory and rank its largest immediate children.

## Layout

```
disk_cleanup.rb              command line entry point
lib/disk_cleanup.rb          requires the library
lib/disk_cleanup/*.rb        one responsibility per file
test/disk_cleanup/*_test.rb  tests mirroring lib/
```

- `options.rb` parses the command line into `Settings`
- `inventory.rb` finds what to clean, `usage_guard.rb` skips what a running process is using, `worktree_guard.rb` keeps worktrees that hold local work
- `removal.rb` deletes and verifies, `disk_usage.rb` measures
- `usage_map.rb` and `reporter.rb` render the map and the cleanup summary
- `run_log.rb` appends one timestamped line per run to `~/.disk_cleanup.log`
- `runner.rb` ties the pieces together

## Checks

```bash
gem install rubocop
rake lint     # rubocop
rake test     # test suite
rake          # both
```

The same checks run in CI on every push to `main` and on every pull request.

## Pre-commit Hooks

Install the hook once per clone (requires [pre-commit](https://pre-commit.com), for example `brew install pre-commit`):

```bash
pre-commit install
```

Every commit then runs rubocop over the staged Ruby files and the full test suite. Rubocop applies its safe corrections and aborts the commit so the changes can be reviewed. To run the hooks manually:

```bash
pre-commit run --all-files
```

## Notes

- `--dry-run` uses the same discovery logic as live cleanup
- `--map` and per-path sizes use allocated disk blocks (`st_blocks`), so sparse VM images are not reported at their logical hole size
- project cleanup walks the project tree recursively and prunes matching cache/build directories in place
- missing paths are ignored
- Docker cleanup removes local Docker Desktop data and Colima VM data (`~/.colima`), so images, containers, and volumes will need to be recreated or pulled again
- `agents` removes Codex and Grok session history and downloaded installers; those chat transcripts are not recoverable, so exclude the category with `--skip=agents` when the history matters
- `worktrees` only removes worktrees whose working tree is clean and whose branch has nothing ahead of its upstream; detached worktrees and worktrees without an upstream are left in place
- Apple-protected entries under `~/Library/Caches` are left alone instead of being counted as removal failures
- directories used by a running process are skipped and listed at the end of the report; `--force` removes them anyway
- leftovers the system itself protects, such as an orphan `~/Library/Containers/com.docker.docker` from an uninstalled Docker Desktop, are listed as `Protected by macOS (left alone)` and never fail a run
- a process marks a directory as in use when its working directory is inside that directory, or when the directory is inside the process working directory (a dev server running at the project root, for example). Broad locations such as the home directory, `Desktop`, `Downloads`, `Library`, and the projects root are not treated as "in use"
- `--min-age-days=DAYS` only removes Downloads installers and Trash items older than `DAYS`, based on modification time; the default is `0` (no age filter)
- every run appends a line with the timestamp, mode, removed bytes, and failure count to `~/.disk_cleanup.log` (or `<--home>/.disk_cleanup.log`); the console also prints a `Started:` line
- the exit status is `1` when any planned path could not be removed; the failures are listed at the end of the report. macOS-protected paths are reported separately and do not affect the exit status
