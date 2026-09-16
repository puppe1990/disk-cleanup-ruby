# frozen_string_literal: true

module DiskCleanup
  # One section of the usage map, such as Home or Projects.
  UsageSection = Struct.new(:title, :entries, keyword_init: true)

  # Ranks the largest paths in the areas this script knows about. Nothing is
  # deleted here, so `--map` is safe to run at any time.
  class UsageMap
    def initialize(settings)
      @settings = settings
    end

    def sections
      return [section("Path", PathListing.existing_children(@settings.map_path))] if @settings.map_path

      [
        section("Home", home_paths),
        section("Projects", PathListing.directories(@settings.projects_root)),
        section("Application Support", PathListing.directories(application_support_root))
      ]
    end

    private

    def section(title, paths)
      entries = paths
        .select { |path| File.exist?(path) }
        .map { |path| MeasuredPath.new(path: path, bytes: DiskUsage.bytes_for(path)) }
        .sort_by { |entry| [-entry.bytes, entry.path] }
        .first(@settings.report_limit)

      UsageSection.new(title: title, entries: entries)
    end

    def home_paths
      top_level = PathListing.directories(@settings.home)
      top_level.reject { |path| excluded_home_paths.include?(path) }
    end

    def excluded_home_paths
      [@settings.projects_root, File.join(@settings.home, "Library")]
    end

    def application_support_root
      File.join(@settings.home, "Library", "Application Support")
    end
  end
end
