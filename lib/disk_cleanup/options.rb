# frozen_string_literal: true

require "optparse"

module DiskCleanup
  # Everything a run needs, with explicit fields so a typo raises instead of
  # silently returning nil.
  Settings = Struct.new(
    :dry_run,
    :map_only,
    :map_path,
    :home,
    :projects_root,
    :categories,
    :report_limit,
    :min_age_days,
    :force,
    keyword_init: true
  )

  # Parses the command line into Settings.
  class Options
    CATEGORY_NAMES = %w[trash downloads caches homebrew docker claude projects].freeze

    def self.parse(argv)
      settings = defaults
      parser = OptionParser.new { |opts| define_options(opts, settings) }
      parser.parse!(argv)
      finalized(settings)
    end

    def self.defaults
      Settings.new(
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
    end

    def self.finalized(settings)
      settings.projects_root ||= File.join(settings.home, "Desktop", "Projetos")
      settings.categories = settings.categories.uniq
      settings
    end

    def self.define_options(opts, settings)
      opts.banner = "Usage: ruby disk_cleanup.rb [options]"

      define_cleanup_options(opts, settings)
      define_target_options(opts, settings)
      define_category_options(opts, settings)
      define_report_options(opts, settings)

      opts.on("-h", "--help", "Show help") do
        puts opts
        exit 0
      end
    end

    def self.define_cleanup_options(opts, settings)
      opts.on("--dry-run", "Show what would be removed without deleting") do
        settings.dry_run = true
      end

      opts.on("--min-age-days=DAYS", Integer, "Only remove Downloads/Trash items older than DAYS") do |value|
        raise ArgumentError, "--min-age-days must be zero or greater" if value.negative?

        settings.min_age_days = value
      end

      opts.on("--force", "Remove paths even when a running process is using them") do
        settings.force = true
      end
    end

    def self.define_target_options(opts, settings)
      opts.on("--home=PATH", "Override home directory") do |value|
        settings.home = File.expand_path(value)
      end

      opts.on("--projects-root=PATH", "Override projects root") do |value|
        settings.projects_root = File.expand_path(value)
      end
    end

    def self.define_category_options(opts, settings)
      opts.on("--only=LIST", "Comma-separated categories to include") do |value|
        settings.categories = validate_categories(value.split(","))
      end

      opts.on("--skip=LIST", "Comma-separated categories to exclude") do |value|
        settings.categories -= validate_categories(value.split(","))
      end
    end

    def self.define_report_options(opts, settings)
      opts.on("--map", "Show the largest directories in key areas without deleting") do
        settings.map_only = true
      end

      opts.on("--map-path=PATH", "Show the largest children under a specific directory") do |value|
        settings.map_only = true
        settings.map_path = File.expand_path(value, settings.home)
      end

      opts.on("--top=N", Integer, "Limit report rows per section (default: 10)") do |value|
        raise ArgumentError, "--top must be greater than 0" unless value.positive?

        settings.report_limit = value
      end
    end

    def self.validate_categories(categories)
      normalized = categories.map(&:strip).reject(&:empty?)
      invalid = normalized - CATEGORY_NAMES
      raise ArgumentError, "Unknown category: #{invalid.join(', ')}" if invalid.any?

      normalized
    end
  end
end
