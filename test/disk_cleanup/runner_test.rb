# frozen_string_literal: true

require_relative "../test_helper"

class RunnerTest < DiskCleanupTest
  def test_live_execution_removes_planned_download_files
    with_home do |home|
      downloads = File.join(home, "Downloads")
      removable = write_file(File.join(downloads, "installer.dmg"))
      kept = write_file(File.join(downloads, "notes.txt"))

      runner_for(home, "--only=downloads").execute(io: StringIO.new)

      refute File.exist?(removable)
      assert File.exist?(kept)
    end
  end

  def test_live_execution_removes_claude_vm_data_and_keeps_local_storage
    with_home do |home|
      claude = File.join(home, "Library", "Application Support", "Claude")
      vm_bundles = File.join(claude, "vm_bundles")
      cache = File.join(claude, "Cache")
      code_vm = File.join(claude, "claude-code-vm")
      local_storage = File.join(claude, "Local Storage")

      [vm_bundles, cache, code_vm, local_storage].each do |path|
        FileUtils.mkdir_p(path)
        File.write(File.join(path, "payload"), "x")
      end

      runner_for(home, "--only=claude").execute(io: StringIO.new)

      refute File.exist?(vm_bundles)
      refute File.exist?(cache)
      refute File.exist?(code_vm)
      assert File.exist?(local_storage)
    end
  end

  def test_failures_are_reported_and_do_not_stop_other_categories
    skip "requires directory permissions" if Process.uid.zero?

    with_home do |home|
      downloads = File.join(home, "Downloads")
      FileUtils.mkdir_p(downloads)
      blocked = write_file(File.join(downloads, "blocked.dmg"))
      trashed = write_file(File.join(home, ".Trash", "junk.txt"))

      File.chmod(0o500, downloads)
      begin
        io = StringIO.new
        failures = runner_for(home, "--only=downloads,trash").execute(io: io)

        assert_equal [blocked], failures.map(&:path)
        refute File.exist?(trashed)
        assert_includes io.string, "Failed to remove: 1 item(s)"
        assert_includes io.string, "#{blocked} (parent directory is not writable)"
      ensure
        File.chmod(0o700, downloads)
      end
    end
  end

  def test_execution_is_recorded_in_the_run_log_and_console
    with_home do |home|
      downloads = File.join(home, "Downloads")
      write_payload(File.join(downloads, "installer.dmg"), 1)

      io = StringIO.new
      runner_for(home, "--only=downloads", "--dry-run").execute(io: io)

      assert_includes io.string, "Started:"
      log = File.read(File.join(home, ".disk_cleanup.log"))
      assert_match(/mode=dry-run/, log)
      assert_match(/removed=\S+/, log)
      assert_match(/failures=0/, log)
    end
  end

  def test_dry_run_reports_no_removal_failures
    skip "requires directory permissions" if Process.uid.zero?

    with_home do |home|
      downloads = File.join(home, "Downloads")
      FileUtils.mkdir_p(downloads)
      blocked = write_file(File.join(downloads, "blocked.dmg"))

      File.chmod(0o500, downloads)
      begin
        io = StringIO.new
        failures = runner_for(home, "--only=downloads", "--dry-run").execute(io: io)

        assert_empty failures
        refute_includes io.string, "Failed to remove"
        assert File.exist?(blocked)
      ensure
        File.chmod(0o700, downloads)
      end
    end
  end

  def test_cli_exits_with_error_when_a_path_cannot_be_removed
    skip "requires directory permissions" if Process.uid.zero?

    with_home do |home|
      downloads = File.join(home, "Downloads")
      FileUtils.mkdir_p(downloads)
      File.write(File.join(downloads, "blocked.dmg"), "x")
      File.chmod(0o500, downloads)

      begin
        output, status = Open3.capture2e(RbConfig.ruby, SCRIPT, "--home=#{home}", "--only=downloads")

        assert_equal 1, status.exitstatus
        assert_includes output, "Failed to remove"
      ensure
        File.chmod(0o700, downloads)
      end
    end
  end

  def test_protected_paths_are_listed_and_do_not_fail_the_run
    with_home do |home|
      downloads = File.join(home, "Downloads")
      left_alone = write_file(File.join(downloads, "container.dmg"))

      io = StringIO.new
      removal = DiskCleanup::Removal.new(file_utils: RefusingFileUtils.new)
      failures = runner_for(home, "--only=downloads", removal: removal).execute(io: io)

      assert_empty failures
      assert File.exist?(left_alone)
      assert_includes io.string, "Protected by macOS (left alone): 1 item(s)"
      assert_includes io.string, left_alone
      refute_includes io.string, "Failed to remove"
      assert_match(/failures=0/, File.read(File.join(home, ".disk_cleanup.log")))
    end
  end
end
