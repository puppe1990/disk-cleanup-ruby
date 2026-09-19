# frozen_string_literal: true

require "find"

module DiskCleanup
  # One cleanup unit: the entries to remove and the paths left alone because a
  # running process is using them.
  Action = Struct.new(:category, :label, :entries, :skipped, keyword_init: true) do
    def paths
      entries.map(&:path)
    end

    def bytes
      entries.sum(&:bytes)
    end
  end

  # Finds the paths each category would remove, with their sizes.
  class Inventory
    DOWNLOAD_EXTENSIONS = %w[.dmg .zip .pkg .iso].freeze
    TOOL_CACHE_PATHS = %w[
      .npm/_cacache
      .npm/_npx
      .cache
      .bun/install/cache
      .cargo/registry
      Library/pnpm/store
    ].freeze
    APPLE_CACHE_NAMES = %w[CloudKit FamilyCircle Safari GeoServices].freeze
    PROJECT_DIR_NAMES = %w[
      node_modules
      .next
      dist
      build
      .turbo
      .cache
      coverage
      target
      output
      output_directory
      tmp
      .zig-cache
      .elixir_ls
      _build
      deps
      .netlify
      .pytest_cache
      .venv
      venv
    ].freeze

    def initialize(settings, usage_guard: UsageGuard.new(settings))
      @settings = settings
      @usage_guard = usage_guard
    end

    def actions
      @settings.categories.flat_map { |category| send("plan_#{category}") }
    end

    private

    def plan_trash
      children = PathListing.existing_children(File.join(@settings.home, ".Trash"))
        .select { |path| older_than_min_age?(path) }
      [build_action("trash", "Empty ~/.Trash", children)]
    end

    def plan_downloads
      files = PathListing.safe_glob(File.join(@settings.home, "Downloads", "*"))
        .select { |path| File.file?(path) && DOWNLOAD_EXTENSIONS.include?(File.extname(path).downcase) }
        .select { |path| older_than_min_age?(path) }
      [build_action("downloads", "Remove installer/archive files from ~/Downloads", files)]
    end

    def plan_caches
      paths = PathListing.existing_children(File.join(@settings.home, "Library", "Caches"))
        .reject { |path| skip_library_cache?(path) } + tool_cache_paths
      [build_action("caches", "Remove regenerable caches", paths)]
    end

    def skip_library_cache?(path)
      return true unless writable_path?(path)

      apple_system_cache?(File.basename(path))
    end

    def writable_path?(path)
      File.writable?(path)
    rescue SystemCallError
      false
    end

    def apple_system_cache?(name)
      name.start_with?("com.apple.") || APPLE_CACHE_NAMES.include?(name)
    end

    def tool_cache_paths
      TOOL_CACHE_PATHS.filter_map do |relative|
        path = File.join(@settings.home, relative)
        path if File.exist?(path)
      end
    end

    def plan_homebrew
      path = File.join(@settings.home, "Library", "Caches", "Homebrew", "downloads")
      [build_action("homebrew", "Remove Homebrew downloads cache", existing_path(path))]
    end

    def plan_docker
      paths = [
        File.join(@settings.home, "Library", "Containers", "com.docker.docker"),
        File.join(@settings.home, "Library", "Application Support", "Docker"),
        File.join(@settings.home, "Library", "Application Support", "Docker Desktop"),
        File.join(@settings.home, ".colima")
      ].select { |path| File.exist?(path) }

      [build_action("docker", "Remove Docker Desktop and Colima local data", paths)]
    end

    def plan_claude
      root = File.join(@settings.home, "Library", "Application Support", "Claude")
      paths = %w[vm_bundles Cache claude-code-vm].flat_map do |name|
        existing_path(File.join(root, name))
      end
      [build_action("claude", "Remove Claude VM bundles and caches", paths)]
    end

    def plan_projects
      root = @settings.projects_root
      return [build_action("projects", "Remove regenerable project artifacts", [])] unless Dir.exist?(root)

      paths = []
      Find.find(root) do |path|
        next unless File.directory?(path)

        if project_regenerable_directory?(File.basename(path))
          paths << path
          Find.prune
        end
      end

      [build_action("projects", "Remove regenerable project artifacts", paths)]
    end

    def project_regenerable_directory?(basename)
      PROJECT_DIR_NAMES.include?(basename) || basename.start_with?(".next-")
    end

    def build_action(category, label, paths)
      skipped, removable = paths.compact.uniq.partition { |path| @usage_guard.in_use?(path) }

      Action.new(
        category: category,
        label: label,
        entries: removable.map { |path| MeasuredPath.new(path: path, bytes: DiskUsage.bytes_for(path)) },
        skipped: skipped
      )
    end

    def older_than_min_age?(path)
      return true if @settings.min_age_days.zero?

      File.lstat(path).mtime <= Time.now - (@settings.min_age_days * 86_400)
    rescue SystemCallError
      false
    end

    def existing_path(path)
      File.exist?(path) ? [path] : []
    end
  end
end
