# frozen_string_literal: true

require_relative "../test_helper"

class RunLogTest < DiskCleanupTest
  def test_appends_a_timestamped_line_per_run
    with_home do |home|
      log = DiskCleanup::RunLog.new(parse_options(home))

      log.record(started_at: Time.local(2026, 9, 24, 15, 15, 0), mode: "live", removed_total: 1024, failure_count: 2)
      log.record(started_at: Time.local(2026, 9, 25, 8, 0, 0), mode: "dry-run", removed_total: 0, failure_count: 0)

      lines = File.readlines(File.join(home, ".disk_cleanup.log"), chomp: true)
      assert_equal "2026-09-24 15:15:00 | mode=live | removed=1.0 KiB | failures=2", lines[0]
      assert_equal "2026-09-25 08:00:00 | mode=dry-run | removed=0 B | failures=0", lines[1]
    end
  end
end
