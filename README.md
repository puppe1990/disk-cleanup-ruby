# disk-cleanup-ruby

Ruby script to reclaim disk space on macOS by removing regenerable caches, Docker Desktop data, project build artifacts, trash contents, and installer/archive files from `Downloads`.

## What It Cleans

- `trash`: empty `~/.Trash`
- `downloads`: remove `*.dmg`, `*.zip`, `*.pkg`, `*.iso` from `~/Downloads`
- `caches`: remove `~/.npm/_cacache`, `~/.cache`, `~/.bun/install/cache`, and children under `~/Library/Caches`
- `homebrew`: remove `~/Library/Caches/Homebrew/downloads`
- `docker`: remove Docker Desktop local data directories
- `projects`: remove regenerable directories like `node_modules`, `.next`, `dist`, `build`, `.turbo`, `.cache`, `coverage` under `~/Desktop/Projetos`

## Usage

```bash
ruby disk_cleanup.rb --dry-run
ruby disk_cleanup.rb
ruby disk_cleanup.rb --only=downloads,caches,homebrew
ruby disk_cleanup.rb --skip=docker
```

## Tests

```bash
ruby test_disk_cleanup.rb
```

## Notes

- `--dry-run` uses the same discovery logic as live cleanup
- missing paths are ignored
- Docker cleanup removes local Docker Desktop data, so images, containers, and volumes will need to be recreated or pulled again
