# frozen_string_literal: true

module DiskCleanup
  # Tells whether a directory is being used by a running process. A directory is
  # in use when a process working directory sits inside it, or when it sits
  # inside a process working directory, except for broad locations such as the
  # home directory itself.
  class UsageGuard
    def initialize(options, working_directories: nil)
      @options = options
      @injected_working_directories = working_directories
    end

    def in_use?(path)
      return false if @options.force
      return false unless File.directory?(path)

      target = canonical_path(path)
      working_directories.any? { |dir| process_uses?(dir, target) }
    end

    private

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
      @container_directories ||= container_directory_paths.map { |dir| canonical_path(dir) }.uniq
    end

    def container_directory_paths
      [
        @options.home,
        File.join(@options.home, "Desktop"),
        File.join(@options.home, "Downloads"),
        File.join(@options.home, ".Trash"),
        File.join(@options.home, "Library"),
        File.join(@options.home, "Library", "Caches"),
        File.join(@options.home, "Library", "Application Support"),
        File.join(@options.home, "Library", "Containers"),
        @options.projects_root
      ]
    end

    def working_directories
      @working_directories ||= detected_working_directories.map { |dir| canonical_path(dir) }.uniq
    end

    def detected_working_directories
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
  end
end
