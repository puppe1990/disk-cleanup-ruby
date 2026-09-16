#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "find"
require "optparse"
require "ostruct"

module DiskCleanup
  Action = Struct.new(:category, :label, :entries, :skipped, keyword_init: true) do
    def paths
      entries.map(&:path)
    end

    def bytes
      entries.sum(&:bytes)
    end
  end
  ReportEntry = Struct.new(:path, :bytes, keyword_init: true)
  ReportSection = Struct.new(:title, :entries, keyword_init: true)

  class Options
    CATEGORY_NAMES = %w[trash downloads caches homebrew docker claude projects].freeze
    DOWNLOAD_EXTENSIONS = %w[.dmg .zip .pkg .iso].freeze
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
    ].freeze

    def self.parse(argv)
      options = OpenStruct.new(
        dry_run: false,
        map_only: false,
        map_path: nil,
        home: File.expand_path("~"),
        projects_root: nil,
        categories: CATEGORY_NAMES.dup,
        report_limit: 10,
        min_age_days: 0,
        force: false
      )

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: ruby tools/disk_cleanup.rb [options]"

        opts.on("--dry-run", "Show what would be removed without deleting") do
          options.dry_run = true
        end

        opts.on("--map", "Show the largest directories in key areas without deleting") do
          options.map_only = true
        end

        opts.on("--map-path=PATH", "Show the largest children under a specific directory") do |value|
          options.map_only = true
          options.map_path = File.expand_path(value, options.home)
        end

        opts.on("--top=N", Integer, "Limit report rows per section (default: 10)") do |value|
          raise ArgumentError, "--top must be greater than 0" unless value.positive?

          options.report_limit = value
        end

        opts.on("--min-age-days=DAYS", Integer, "Only remove Downloads/Trash items older than DAYS") do |value|
          raise ArgumentError, "--min-age-days must be zero or greater" if value.negative?

          options.min_age_days = value
        end

        opts.on("--force", "Remove paths even when a running process is using them") do
          options.force = true
        end

        opts.on("--only=LIST", "Comma-separated categories to include") do |value|
          options.categories = validate_categories(value.split(","))
        end

        opts.on("--skip=LIST", "Comma-separated categories to exclude") do |value|
          skip = validate_categories(value.split(","))
          options.categories -= skip
        end

        opts.on("--home=PATH", "Override home directory") do |value|
          options.home = File.expand_path(value)
        end

        opts.on("--projects-root=PATH", "Override projects root") do |value|
          options.projects_root = File.expand_path(value)
        end

        opts.on("-h", "--help", "Show help") do
          puts opts
          exit 0
        end
      end

      parser.parse!(argv)
      options.projects_root ||= File.join(options.home, "Desktop", "Projetos")
      options.categories = options.categories.uniq
      options
    end

    def self.validate_categories(categories)
      normalized = categories.map(&:strip).reject(&:empty?)
      invalid = normalized - CATEGORY_NAMES
      raise ArgumentError, "Unknown category: #{invalid.join(', ')}" if invalid.any?

      normalized
    end
  end

  class Runner
    CATEGORY_NAMES = Options::CATEGORY_NAMES

    def initialize(options, working_directories: nil)
      @options = options
      @injected_working_directories = working_directories
    end

    def plan
      @options.categories.flat_map do |category|
        send("plan_#{category}")
      end
    end

    def execute(io: $stdout)
      if @options.map_only
        execute_map(io: io)
        return []
      end

      before = free_bytes("/")
      removed_total = 0
      failures = []
      io.sync = true if io.respond_to?(:sync=)

      io.puts "Disk cleanup"
      io.puts "Mode: #{@options.dry_run ? 'dry-run' : 'live'}"
      io.puts "Free before: #{format_bytes(before)}"
      actions = plan

      actions.each do |action|
        failed = @options.dry_run ? [] : remove_paths(action.paths)
        failures.concat(failed)
        removed = bytes_removed(action, failed)
        removed_total += removed

        note = action.skipped.empty? ? "" : ", #{action.skipped.size} skipped (in use)"
        io.puts "[#{action.category}] #{action.label}: #{action.paths.size} item(s), #{format_bytes(removed)}#{note}"
      end

      after = free_bytes("/")
      io.puts "Free after: #{format_bytes(after)}"
      io.puts "Estimated removed: #{format_bytes(removed_total)}"
      report_skipped(actions, io: io)
      report_failures(failures, io: io)

      failures
    end

    def space_report
      return [build_report_section("Path", existing_children(@options.map_path))] if @options.map_path

      [
        build_report_section("Home", home_report_paths),
        build_report_section("Projects", top_level_children(@options.projects_root)),
        build_report_section("Application Support", top_level_children(application_support_root))
      ]
    end

    private

    def execute_map(io:)
      io.sync = true if io.respond_to?(:sync=)
      io.puts "Disk usage map"

      space_report.each do |section|
        io.puts "Top #{@options.report_limit} in #{section.title}"

        if section.entries.empty?
          io.puts "(no entries found)"
          next
        end

        section.entries.each do |entry|
          io.puts "#{format_bytes(entry.bytes)}\t#{entry.path}"
        end
      end
    end

    def plan_trash
      trash_dir = File.join(@options.home, ".Trash")
      children = existing_children(trash_dir).select { |path| older_than_min_age?(path) }
      [build_action("trash", "Empty ~/.Trash", children)]
    end

    def plan_downloads
      downloads_dir = File.join(@options.home, "Downloads")
      files = safe_glob(File.join(downloads_dir, "*"))
        .select { |path| File.file?(path) && Options::DOWNLOAD_EXTENSIONS.include?(File.extname(path).downcase) }
        .select { |path| older_than_min_age?(path) }
      [build_action("downloads", "Remove installer/archive files from ~/Downloads", files)]
    end

    def plan_caches
      paths = []
      paths.concat(existing_children(File.join(@options.home, "Library", "Caches")))

      %w[
        .npm/_cacache
        .cache
        .bun/install/cache
      ].each do |relative|
        path = File.join(@options.home, relative)
        paths << path if File.exist?(path)
      end

      [build_action("caches", "Remove regenerable caches", paths)]
    end

    def plan_homebrew
      path = File.join(@options.home, "Library", "Caches", "Homebrew", "downloads")
      [build_action("homebrew", "Remove Homebrew downloads cache", existing_path(path))]
    end

    def plan_docker
      paths = [
        File.join(@options.home, "Library", "Containers", "com.docker.docker"),
        File.join(@options.home, "Library", "Application Support", "Docker"),
        File.join(@options.home, "Library", "Application Support", "Docker Desktop")
      ].select { |path| File.exist?(path) }

      [build_action("docker", "Remove Docker Desktop local data", paths)]
    end

    def plan_claude
      path = File.join(@options.home, "Library", "Application Support", "Claude", "vm_bundles")
      [build_action("claude", "Remove Claude VM bundles", existing_path(path))]
    end

    def plan_projects
      root = @options.projects_root
      return [build_action("projects", "Remove regenerable project artifacts", [])] unless Dir.exist?(root)

      paths = []
      Find.find(root) do |path|
        next unless File.directory?(path)

        basename = File.basename(path)
        if project_regenerable_directory?(basename)
          paths << path
          Find.prune
        end
      end

      [build_action("projects", "Remove regenerable project artifacts", paths)]
    end

    def project_regenerable_directory?(basename)
      Options::PROJECT_DIR_NAMES.include?(basename)
    end

    def build_action(category, label, paths)
      skipped, removable = paths.compact.uniq.partition { |path| path_in_use?(path) }

      Action.new(
        category: category,
        label: label,
        entries: removable.map { |path| ReportEntry.new(path: path, bytes: size_for(path)) },
        skipped: skipped
      )
    end

    def build_report_section(title, paths)
      entries = paths
        .select { |path| File.exist?(path) }
        .map { |path| ReportEntry.new(path: path, bytes: size_for(path)) }
        .sort_by { |entry| [-entry.bytes, entry.path] }
        .first(@options.report_limit)

      ReportSection.new(title: title, entries: entries)
    end

    def older_than_min_age?(path)
      return true if @options.min_age_days.zero?

      File.lstat(path).mtime <= Time.now - (@options.min_age_days * 86_400)
    rescue SystemCallError
      false
    end

    def remove_paths(paths)
      paths.reject { |path| remove_path(path) }
    end

    def remove_path(path)
      FileUtils.rm_rf(path, secure: true)
      !path_present?(path)
    rescue StandardError
      false
    end

    def path_present?(path)
      File.lstat(path)
      true
    rescue Errno::ENOENT
      false
    end

    def bytes_removed(action, failed)
      return action.bytes if failed.empty?

      action.entries.reject { |entry| failed.include?(entry.path) }.sum(&:bytes)
    end

    def report_skipped(actions, io:)
      skipped = actions.flat_map(&:skipped)
      return if skipped.empty?

      io.puts "Skipped (in use, use --force to remove): #{skipped.size} item(s)"
      skipped.each { |path| io.puts "  #{path}" }
    end

    def report_failures(failures, io:)
      return if failures.empty?

      io.puts "Failed to remove: #{failures.size} item(s)"
      failures.each { |path| io.puts "  #{path}" }
    end

    def path_in_use?(path)
      return false if @options.force
      return false unless File.directory?(path)

      target = canonical_path(path)
      working_directories.any? { |dir| process_uses?(dir, target) }
    end

    def process_uses?(dir, path)
      return false if container_directory?(dir)

      dir == path || within?(dir, path) || within?(path, dir)
    end

    def within?(path, dir)
      path.start_with?("#{dir}/")
    end

    def container_directory?(dir)
      container_directories.include?(dir)
    end

    def container_directories
      @container_directories ||= [
        @options.home,
        File.join(@options.home, "Desktop"),
        File.join(@options.home, "Downloads"),
        File.join(@options.home, ".Trash"),
        File.join(@options.home, "Library"),
        File.join(@options.home, "Library", "Caches"),
        File.join(@options.home, "Library", "Application Support"),
        File.join(@options.home, "Library", "Containers"),
        @options.projects_root
      ].map { |dir| canonical_path(dir) }.uniq
    end

    def working_directories
      @working_directories ||= process_working_directories.map { |dir| canonical_path(dir) }.uniq
    end

    def process_working_directories
      @injected_working_directories || lsof_working_directories
    end

    def lsof_working_directories
      `lsof -d cwd -Fn 2>/dev/null`.lines.filter_map { |line| line[1..].chomp if line.start_with?("n") }
    rescue Errno::ENOENT
      []
    end

    def canonical_path(path)
      File.realpath(path)
    rescue SystemCallError
      path
    end

    def existing_path(path)
      File.exist?(path) ? [path] : []
    end

    def existing_children(dir)
      return [] unless Dir.exist?(dir)

      safe_glob(File.join(dir, "*"), File::FNM_DOTMATCH)
        .reject { |path| %w[. ..].include?(File.basename(path)) }
    end

    def top_level_children(dir)
      existing_children(dir).select { |path| File.directory?(path) }
    end

    def home_report_paths
      excluded = [
        @options.projects_root,
        File.join(@options.home, "Library")
      ]

      top_level_children(@options.home).reject do |path|
        excluded.include?(path)
      end
    end

    def application_support_root
      File.join(@options.home, "Library", "Application Support")
    end

    def safe_glob(pattern, flags = 0)
      Dir.glob(pattern, flags)
    rescue Errno::ENOENT, Errno::EACCES, Errno::EPERM
      []
    end

    def size_for(path)
      return 0 unless File.exist?(path)

      if File.file?(path) || File.symlink?(path)
        File.lstat(path).size
      else
        directory_size(path)
      end
    rescue Errno::ENOENT, Errno::EACCES
      0
    end

    def directory_size(dir)
      total = 0
      queue = [dir]

      until queue.empty?
        begin
          current = queue.pop
          stat = File.lstat(current)
          total += stat.size

          next unless File.directory?(current) && !File.symlink?(current)

          Dir.each_child(current) do |child|
            queue << File.join(current, child)
          end
        rescue Errno::ENOENT, Errno::EACCES, Errno::EPERM
          next
        end
      end

      total
    end

    def free_bytes(path)
      stat = Sys::Filesystem.stat(path)
      stat.block_size * stat.blocks_available
    rescue NameError
      `df -k #{Shellwords.escape(path)}`.lines.last.to_s.split[3].to_i * 1024
    end

    def format_bytes(bytes)
      units = %w[B KiB MiB GiB TiB]
      value = bytes.to_f
      unit = units.shift

      while value >= 1024 && !units.empty?
        value /= 1024.0
        unit = units.shift
      end

      if value >= 10 || unit == "B"
        format("%<value>.0f %<unit>s", value: value, unit: unit)
      else
        format("%<value>.1f %<unit>s", value: value, unit: unit)
      end
    end
  end
end

begin
  require "shellwords"
  require "sys/filesystem"
rescue LoadError
  # Fallback to `df` is enough for this standalone script.
end

if $PROGRAM_NAME == __FILE__
  options = DiskCleanup::Options.parse(ARGV)
  failures = DiskCleanup::Runner.new(options).execute
  exit 1 unless failures.empty?
end
