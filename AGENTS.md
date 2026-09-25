# AGENTS.md

Disk cleanup utility for macOS. Pure Ruby, no runtime dependencies.

## Commands

- `rake` — lint + tests, run this before calling work done
- `rake test` — full suite (~0.5s), no setup or database needed
- `rake lint` — rubocop
- `ruby disk_cleanup.rb --dry-run` — exercise the CLI without deleting anything
- `pre-commit run --all-files` — same checks as the git hook

## Layout

- `disk_cleanup.rb` — CLI entry point (parse, run, exit status). Keep it thin.
- `lib/disk_cleanup.rb` — requires every library file.
- `lib/disk_cleanup/*.rb` — one responsibility per file, mirrored by `test/disk_cleanup/*_test.rb`.
- `test/test_helper.rb` — `DiskCleanupTest` base class with tmpdir helpers.
- `docs/` — dated design notes.

## Rules

- Never touch the real home directory in tests: use `with_home` for a tmpdir and pass `--home=<tmpdir>`. `runner_for` defaults to no working directories so the suite stays hermetic; pass `working_directories: nil` only for the real lsof test.
- `Settings` from `Options.parse` is injected everywhere. Do not read ENV or globals inside `lib/`.
- `UsageGuard` decides what a running process is using; its lsof lookup stays injectable through `working_directories:`.
- `WorktreeGuard` only allows removing worktrees with no local changes and no commits ahead of their upstream; its tests build real git repositories in tmpdirs and every git call clears leaked `GIT_*` variables.
- `Removal` re-checks every path after `FileUtils.rm_rf` because rm_rf swallows permission errors. Never report freed bytes without that check.
- All console output goes through `Reporter`; tests assert on the injected `io` string.
- New cleanup category: planner in `inventory.rb`, name in `Options::CATEGORY_NAMES`, a line in the README, and a test.
- Keep methods around 20 lines and files under 300; split by responsibility.

## Caveats

- macOS targeted (`lsof`, `~/Library`, Docker Desktop and Colima paths); the suite also runs on Linux.
- Deleting `node_modules` under a running dev server breaks it. `UsageGuard` skips those paths; `--force` overrides on purpose.
- `--min-age-days` only affects `downloads` and `trash`; other categories are regenerable by definition.
- `DiskUsage.bytes_for` counts allocated blocks, not `st_size`, because Colima/Lima VM disks are sparse.
- `caches` skips Apple system cache directories; do not plan a path that `rm_rf` cannot write.
