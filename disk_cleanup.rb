#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "find"
require "optparse"
require "ostruct"

module DiskCleanup
  Action = Struct.new(:category, :label, :paths, :bytes, keyword_init: true)

  class Options
    CATEGORY_NAMES = %w[trash downloads caches homebrew docker projects].freeze
    DOWNLOAD_EXTENSIONS = %w[.dmg .zip .pkg .iso].freeze
    PROJECT_DIR_NAMES = %w[node_modules .next dist build .turbo .cache coverage].freeze

    def self.parse(argv)
      options = OpenStruct.new(
        dry_run: false,
        home: File.expand_path("~"),
        projects_root: nil,
        categories: CATEGORY_NAMES.dup
      )

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: ruby tools/disk_cleanup.rb [options]"

        opts.on("--dry-run", "Show what would be removed without deleting") do
          options.dry_run = true
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

    def initialize(options)
      @options = options
    end

    def plan
      @options.categories.flat_map do |category|
        send("plan_#{category}")
      end
    end

    def execute(io: $stdout)
      before = free_bytes("/")
      removed_total = 0
      io.sync = true if io.respond_to?(:sync=)

      io.puts "Disk cleanup"
      io.puts "Mode: #{@options.dry_run ? 'dry-run' : 'live'}"
      io.puts "Free before: #{format_bytes(before)}"
      actions = plan

      actions.each do |action|
        removed = if @options.dry_run
                    action.bytes
                  else
                    remove_paths(action.paths)
                    action.bytes
                  end

        removed_total += removed
        io.puts "[#{action.category}] #{action.label}: #{action.paths.size} item(s), #{format_bytes(removed)}"
      end

      after = free_bytes("/")
      io.puts "Free after: #{format_bytes(after)}"
      io.puts "Estimated removed: #{format_bytes(removed_total)}"
    end

    private

    def plan_trash
      trash_dir = File.join(@options.home, ".Trash")
      children = existing_children(trash_dir)
      [build_action("trash", "Empty ~/.Trash", children)]
    end

    def plan_downloads
      downloads_dir = File.join(@options.home, "Downloads")
      files = safe_glob(File.join(downloads_dir, "*"))
        .select { |path| File.file?(path) && Options::DOWNLOAD_EXTENSIONS.include?(File.extname(path).downcase) }
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

    def plan_projects
      root = @options.projects_root
      return [build_action("projects", "Remove regenerable project artifacts", [])] unless Dir.exist?(root)

      paths = []
      Find.find(root) do |path|
        next unless File.directory?(path)

        basename = File.basename(path)
        if Options::PROJECT_DIR_NAMES.include?(basename)
          paths << path
          Find.prune
        end
      end

      [build_action("projects", "Remove regenerable project artifacts", paths)]
    end

    def build_action(category, label, paths)
      unique_paths = paths.compact.uniq
      Action.new(
        category: category,
        label: label,
        paths: unique_paths,
        bytes: unique_paths.sum { |path| size_for(path) }
      )
    end

    def remove_paths(paths)
      paths.each do |path|
        FileUtils.rm_rf(path, secure: true)
      end
    end

    def existing_path(path)
      File.exist?(path) ? [path] : []
    end

    def existing_children(dir)
      return [] unless Dir.exist?(dir)

      safe_glob(File.join(dir, "*"), File::FNM_DOTMATCH)
        .reject { |path| %w[. ..].include?(File.basename(path)) }
    end

    def safe_glob(pattern, flags = 0)
      Dir.glob(pattern, flags)
    rescue Errno::ENOENT
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
  DiskCleanup::Runner.new(options).execute
end
