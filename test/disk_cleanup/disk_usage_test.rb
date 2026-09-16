# frozen_string_literal: true

require_relative "../test_helper"

class DiskUsageTest < DiskCleanupTest
  def test_bytes_for_counts_files_and_directory_entries
    with_home do |home|
      file = write_payload(File.join(home, "blob.bin"), 4)
      write_payload(File.join(home, "nested", "blob.bin"), 2)

      assert_equal 4096, DiskCleanup::DiskUsage.bytes_for(file)
      assert_operator DiskCleanup::DiskUsage.bytes_for(File.join(home, "nested")), :>=, 2048
    end
  end

  def test_bytes_for_missing_path_is_zero
    with_home do |home|
      assert_equal 0, DiskCleanup::DiskUsage.bytes_for(File.join(home, "missing"))
    end
  end

  def test_free_bytes_reports_available_space
    assert_operator DiskCleanup::DiskUsage.free_bytes("/"), :>, 0
  end
end
