# frozen_string_literal: true

require_relative "../test_helper"

class RemovalTest < DiskCleanupTest
  def test_removes_directories_with_their_contents
    with_home do |home|
      node_modules = File.join(home, "node_modules")
      FileUtils.mkdir_p(File.join(node_modules, "pkg"))
      File.write(File.join(node_modules, "pkg", "index.js"), "x")

      failures = DiskCleanup::Removal.new.remove_paths([node_modules])

      assert_empty failures
      refute File.exist?(node_modules)
    end
  end

  def test_missing_paths_are_not_failures
    with_home do |home|
      failures = DiskCleanup::Removal.new.remove_paths([File.join(home, "already-gone")])

      assert_empty failures
    end
  end

  def test_reports_a_reason_when_the_parent_directory_is_not_writable
    skip "requires directory permissions" if Process.uid.zero?

    with_home do |home|
      locked = File.join(home, "locked")
      FileUtils.mkdir_p(locked)
      blocked = write_file(File.join(locked, "keep.dmg"))
      File.chmod(0o500, locked)

      begin
        failures = DiskCleanup::Removal.new.remove_paths([blocked])

        assert_equal 1, failures.size
        assert_equal blocked, failures.first.path
        assert_equal "parent directory is not writable", failures.first.reason
        assert_includes failures.first.to_s, blocked
      ensure
        File.chmod(0o700, locked)
      end
    end
  end

  def test_system_protected_paths_are_marked_and_left_alone
    with_home do |home|
      container = File.join(home, "Library", "Containers", "com.docker.docker")
      FileUtils.mkdir_p(container)
      File.write(File.join(container, ".com.apple.containermanagerd.metadata.plist"), "x")

      removal = DiskCleanup::Removal.new(file_utils: RefusingFileUtils.new)
      survivors = removal.remove_paths([container])

      assert_equal 1, survivors.size
      assert_equal container, survivors.first.path
      assert_equal "protected by macOS", survivors.first.reason
      assert survivors.first.protected?
    end
  end
end
