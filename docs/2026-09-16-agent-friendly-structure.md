# Agent-Friendly Structure

## Why

The script grew to 511 lines in one file and the suite to 641, past the point where a single
read fits comfortably and where one edit has one obvious place to go. Long files also make
grep noisy: `remove_paths` and `plan_*` lived in the same class as byte formatting and lsof
parsing, so a search for one concern returned hits from all of them.

The primary reader of this repository is now an agent loop, which pays for every tool call and
loses attention before it hits the context limit. Small files with unique names are cheaper to
navigate than one cohesive-but-large file.

## Layout

- `disk_cleanup.rb` stays the entry point at the repository root: parse, run, exit status.
  Every documented command keeps working.
- `lib/disk_cleanup/*.rb` holds one responsibility per file: options, inventory, usage guard,
  removal, disk usage, path listing, usage map, reporter, runner.
- `test/disk_cleanup/*_test.rb` mirrors those paths, plus `test/test_helper.rb` with the shared
  tmpdir helpers.
- `Rakefile` exposes `rake lint`, `rake test` and `rake` for both.

## Trade-off

The script is no longer a single file that can be copied to another machine with `scp`. The
repository remains dependency-free and `ruby disk_cleanup.rb` is still the only command needed
to run a cleanup; if a portable single file is ever needed again, bundle the library with a
build step rather than growing one file back.
