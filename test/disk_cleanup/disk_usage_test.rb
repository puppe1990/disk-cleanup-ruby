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

  def test_bytes_for_counts_allocated_blocks_not_logical_size
    with_home do |home|
      path = File.join(home, "sparse.img")
      File.open(path, "wb") do |file|
        file.seek((32 * 1024 * 1024) - 1)
        file.write("x")
      end

      stat = File.lstat(path)
      allocated = stat.blocks * 512
      skip "filesystem did not create a sparse file" unless allocated < stat.size

      assert_equal allocated, DiskCleanup::DiskUsage.bytes_for(path)
      assert_operator DiskCleanup::DiskUsage.bytes_for(path), :<, 1024 * 1024
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
