# frozen_string_literal: true

require "fileutils"

module DiskCleanup
  # Removes the planned paths. FileUtils#rm_rf swallows permission errors, so
  # every path is checked afterwards and the surviving ones are returned as
  # failures instead of being counted as freed space.
  class Removal
    Failure = Struct.new(:path, :reason, keyword_init: true) do
      def to_s
        "#{path} (#{reason})"
      end
    end

    def remove_paths(paths)
      paths.filter_map { |path| remove_path(path) }
    end

    private

    def remove_path(path)
      FileUtils.rm_rf(path, secure: true)
      return nil unless path_remains?(path)

      Failure.new(path: path, reason: blocker_reason(path))
    rescue StandardError => e
      Failure.new(path: path, reason: e.message)
    end

    def blocker_reason(path)
      return "parent directory is not writable" unless File.writable?(File.dirname(path))
      return "path is not writable" unless File.writable?(path)

      "path survived rm_rf"
    end

    def path_remains?(path)
      File.lstat(path)
      true
    rescue Errno::ENOENT
      false
    end
  end
end
