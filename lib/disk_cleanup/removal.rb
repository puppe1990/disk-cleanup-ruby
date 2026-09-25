# frozen_string_literal: true

require "fileutils"

module DiskCleanup
  # Removes the planned paths. FileUtils#rm_rf swallows permission errors, so
  # every path is checked afterwards and the surviving ones are returned as
  # failures instead of being counted as freed space. The removal backend is
  # injectable so tests can reproduce a system-protected path without EPERM.
  class Removal
    SURVIVED = "path survived rm_rf"
    PROTECTED = "protected by macOS"

    # A path still on disk after removal. Paths the system itself refuses to
    # delete, such as orphan app containers, are marked as protected: they are
    # left alone without failing the run.
    Failure = Struct.new(:path, :reason, :protected, keyword_init: true) do
      def protected?
        protected
      end

      def to_s
        "#{path} (#{reason})"
      end
    end

    def initialize(file_utils: FileUtils)
      @file_utils = file_utils
    end

    def remove_paths(paths)
      paths.filter_map { |path| remove_path(path) }
    end

    private

    def remove_path(path)
      @file_utils.rm_rf(path, secure: true)
      return nil unless path_remains?(path)

      surviving_failure(path)
    rescue StandardError => e
      Failure.new(path: path, reason: e.message)
    end

    def surviving_failure(path)
      reason = blocker_reason(path)
      return Failure.new(path: path, reason: reason) unless reason == SURVIVED

      direct_removal_failure(path)
    end

    # rm_rf hides the real error, so a direct removal is attempted to learn
    # why the path is still there. macOS refuses app container leftovers with
    # EPERM even though their permission bits look writable.
    def direct_removal_failure(path)
      @file_utils.remove_entry(path)
      path_remains?(path) ? Failure.new(path: path, reason: SURVIVED) : nil
    rescue Errno::EPERM
      Failure.new(path: path, reason: PROTECTED, protected: true)
    end

    def blocker_reason(path)
      return "parent directory is not writable" unless File.writable?(File.dirname(path))
      return "path is not writable" unless File.writable?(path)

      SURVIVED
    end

    def path_remains?(path)
      File.lstat(path)
      true
    rescue Errno::ENOENT
      false
    end
  end
end
