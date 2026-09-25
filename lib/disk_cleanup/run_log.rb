# frozen_string_literal: true

require "fileutils"

module DiskCleanup
  # Appends one timestamped line per run to a log file so past executions can
  # be reviewed. The path lives under the configured home directory, which
  # keeps tests inside their tmpdir instead of the real home.
  class RunLog
    FILENAME = ".disk_cleanup.log"

    def initialize(settings)
      @path = File.join(settings.home, FILENAME)
    end

    def record(started_at:, mode:, removed_total:, failure_count:)
      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, "a") { |file| file.puts(line(started_at, mode, removed_total, failure_count)) }
    end

    private

    def line(started_at, mode, removed_total, failure_count)
      "#{started_at.strftime('%Y-%m-%d %H:%M:%S')} | mode=#{mode} | " \
        "removed=#{ByteFormat.format_bytes(removed_total)} | failures=#{failure_count}"
    end
  end
end
