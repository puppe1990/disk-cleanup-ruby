# Disk Cleanup Script Design

## Goal

Create a standalone Ruby script that repeats the disk cleanup performed on April 4, 2026 without tying the logic to a specific project repository.

## Scope

The script will clean the same categories handled manually:

- `trash`: empty `~/.Trash`
- `downloads`: remove installer/archive files from `~/Downloads` matching `*.dmg`, `*.zip`, `*.pkg`, `*.iso`
- `caches`: remove regenerable caches from `~/.npm/_cacache`, `~/.cache`, `~/.bun/install/cache`, and children under `~/Library/Caches`
- `homebrew`: remove `~/Library/Caches/Homebrew/downloads`
- `docker`: remove Docker Desktop local data directories under `~/Library/Containers/com.docker.docker`, `~/Library/Application Support/Docker`, and `~/Library/Application Support/Docker Desktop`
- `projects`: remove regenerable build/dependency directories inside `~/Desktop/Projetos`: `node_modules`, `.next`, `dist`, `build`, `.turbo`, `.cache`, `coverage`

## Interface

The script will live at `tools/disk_cleanup.rb` and support:

- `--dry-run`: report what would be removed without deleting
- `--only=a,b,c`: run only selected categories
- `--skip=a,b,c`: skip selected categories
- `--projects-root=PATH`: override the default projects root for project artifact cleanup
- `--home=PATH`: override home directory for controlled testing
- `--min-age-days=DAYS`: only remove `downloads` and `trash` items older than `DAYS` days
- `--force`: remove paths even when a running process is using them

## Output

The script will print:

- disk free space before cleanup
- per-category action summary with removed bytes
- disk free space after cleanup
- total estimated bytes removed

## Safety

- default categories target only regenerable files or clearly disposable installer/archive files
- missing paths are ignored
- `dry-run` uses the same discovery logic as real execution
- directories used by a running process are skipped and reported, unless `--force` is passed
- broad locations (home, `Desktop`, `Downloads`, `Library`, projects root) never count as "in use", so a shell parked there does not block cleanup
- `--min-age-days` keeps recent `downloads` and `trash` items
- paths that could not be removed are reported and the script exits with status `1`
