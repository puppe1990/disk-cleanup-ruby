# frozen_string_literal: true

require_relative "disk_cleanup/path_listing"
require_relative "disk_cleanup/disk_usage"
require_relative "disk_cleanup/options"
require_relative "disk_cleanup/usage_guard"
require_relative "disk_cleanup/removal"
require_relative "disk_cleanup/inventory"
require_relative "disk_cleanup/usage_map"
require_relative "disk_cleanup/reporter"
require_relative "disk_cleanup/runner"

# Reclaims disk space on macOS by removing regenerable caches, Docker Desktop
# data, project build artifacts, trash contents and installer/archive files
# from Downloads. Run it through the disk_cleanup.rb script at the repository
# root, or require this file to drive it from Ruby.
module DiskCleanup
end
