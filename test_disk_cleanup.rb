require "tmpdir"
require "fileutils"
require "open3"
require "minitest/autorun"

require_relative "disk_cleanup"

class DiskCleanupTest < Minitest::Test
  def with_home
    Dir.mktmpdir("disk-cleanup-test") do |dir|
      yield dir
    end
  end

  def test_default_categories_include_all_cleanup_groups
    options = DiskCleanup::Options.parse([])

    assert_equal false, options.dry_run
    assert_equal false, options.map_only
    assert_nil options.map_path
    assert_equal 10, options.report_limit
    assert_equal DiskCleanup::Runner::CATEGORY_NAMES, options.categories
  end

  def test_only_and_skip_flags_filter_categories
    options = DiskCleanup::Options.parse(["--only=downloads,projects,caches", "--skip=projects"])

    assert_equal %w[caches downloads], options.categories.sort
  end

  def test_invalid_category_raises
    error = assert_raises(ArgumentError) do
      DiskCleanup::Options.parse(["--only=nope"])
    end

    assert_match("Unknown category", error.message)
  end

  def test_download_cleanup_matches_supported_extensions
    with_home do |home|
      downloads = File.join(home, "Downloads")
      FileUtils.mkdir_p(downloads)

      removable = %w[a.zip b.dmg c.pkg d.iso].map do |name|
        path = File.join(downloads, name)
        File.write(path, "x")
        path
      end

      kept = File.join(downloads, "keep.mp4")
      File.write(kept, "x")

      options = DiskCleanup::Options.parse(["--home=#{home}", "--only=downloads", "--dry-run"])
      runner = DiskCleanup::Runner.new(options)

      planned = runner.plan
      paths = planned.flat_map(&:paths)

      assert_equal removable.sort, paths.sort
      refute_includes paths, kept
    end
  end

  def test_project_cleanup_finds_regenerable_directories
    with_home do |home|
      projects_root = File.join(home, "Projects")
      node_modules = File.join(projects_root, "app", "node_modules")
      next_dir = File.join(projects_root, "app2", ".next")
      rust_target = File.join(projects_root, "app4", "target")
      output_directory = File.join(projects_root, "app5", "nested", "output_directory")
      zig_cache = File.join(projects_root, "app6", ".zig-cache")
      elixir_build = File.join(projects_root, "app7", "_build")
      deps = File.join(projects_root, "app8", "deps")
      keep_dir = File.join(projects_root, "app3", "src")

      FileUtils.mkdir_p(node_modules)
      FileUtils.mkdir_p(next_dir)
      FileUtils.mkdir_p(rust_target)
      FileUtils.mkdir_p(output_directory)
      FileUtils.mkdir_p(zig_cache)
      FileUtils.mkdir_p(elixir_build)
      FileUtils.mkdir_p(deps)
      FileUtils.mkdir_p(keep_dir)

      options = DiskCleanup::Options.parse([
        "--home=#{home}",
        "--projects-root=#{projects_root}",
        "--only=projects",
        "--dry-run"
      ])

      runner = DiskCleanup::Runner.new(options)
      planned = runner.plan
      paths = planned.flat_map(&:paths)

      assert_includes paths, node_modules
      assert_includes paths, next_dir
      assert_includes paths, rust_target
      assert_includes paths, output_directory
      assert_includes paths, zig_cache
      assert_includes paths, elixir_build
      assert_includes paths, deps
      refute_includes paths, keep_dir
    end
  end

  def test_project_cleanup_handles_common_generated_directories_recursively
    with_home do |home|
      projects_root = File.join(home, "Projects")
      netlify_cache = File.join(projects_root, "site", ".netlify")
      tmp_dir = File.join(projects_root, "app", "tmp")
      build_dir = File.join(projects_root, "app", "build")
      cache_dir = File.join(projects_root, "app", ".cache")

      FileUtils.mkdir_p(netlify_cache)
      FileUtils.mkdir_p(tmp_dir)
      FileUtils.mkdir_p(build_dir)
      FileUtils.mkdir_p(cache_dir)

      options = DiskCleanup::Options.parse([
        "--home=#{home}",
        "--projects-root=#{projects_root}",
        "--only=projects",
        "--dry-run"
      ])

      runner = DiskCleanup::Runner.new(options)
      paths = runner.plan.flat_map(&:paths)

      assert_includes paths, netlify_cache
      assert_includes paths, tmp_dir
      assert_includes paths, build_dir
      assert_includes paths, cache_dir
    end
  end

  def test_cache_cleanup_includes_library_and_tool_caches
    with_home do |home|
      library_cache_child = File.join(home, "Library", "Caches", "com.test.app")
      npm_cache = File.join(home, ".npm", "_cacache")
      generic_cache = File.join(home, ".cache")
      bun_cache = File.join(home, ".bun", "install", "cache")

      [library_cache_child, npm_cache, generic_cache, bun_cache].each do |path|
        FileUtils.mkdir_p(path)
        File.write(File.join(path, "payload"), "x")
      end

      options = DiskCleanup::Options.parse(["--home=#{home}", "--only=caches", "--dry-run"])
      runner = DiskCleanup::Runner.new(options)

      paths = runner.plan.flat_map(&:paths)

      assert_includes paths, library_cache_child
      assert_includes paths, npm_cache
      assert_includes paths, generic_cache
      assert_includes paths, bun_cache
    end
  end

  def test_docker_cleanup_collects_known_docker_directories
    with_home do |home|
      docker_paths = [
        File.join(home, "Library", "Containers", "com.docker.docker"),
        File.join(home, "Library", "Application Support", "Docker"),
        File.join(home, "Library", "Application Support", "Docker Desktop")
      ]

      docker_paths.each do |path|
        FileUtils.mkdir_p(path)
        File.write(File.join(path, "state.json"), "{}")
      end

      options = DiskCleanup::Options.parse(["--home=#{home}", "--only=docker", "--dry-run"])
      runner = DiskCleanup::Runner.new(options)

      paths = runner.plan.flat_map(&:paths)

      assert_equal docker_paths.sort, paths.sort
    end
  end

  def test_claude_cleanup_collects_vm_bundles_only
    with_home do |home|
      vm_bundles = File.join(home, "Library", "Application Support", "Claude", "vm_bundles")
      cache = File.join(home, "Library", "Application Support", "Claude", "Cache")

      FileUtils.mkdir_p(vm_bundles)
      FileUtils.mkdir_p(cache)
      File.write(File.join(vm_bundles, "rootfs.img"), "x")
      File.write(File.join(cache, "index"), "x")

      options = DiskCleanup::Options.parse(["--home=#{home}", "--only=claude", "--dry-run"])
      runner = DiskCleanup::Runner.new(options)

      paths = runner.plan.flat_map(&:paths)

      assert_equal [vm_bundles], paths
      refute_includes paths, cache
    end
  end

  def test_live_execution_removes_planned_download_files
    with_home do |home|
      downloads = File.join(home, "Downloads")
      removable = File.join(downloads, "installer.dmg")
      kept = File.join(downloads, "notes.txt")

      FileUtils.mkdir_p(downloads)
      File.write(removable, "x")
      File.write(kept, "keep")

      options = DiskCleanup::Options.parse(["--home=#{home}", "--only=downloads"])
      runner = DiskCleanup::Runner.new(options)

      runner.execute(io: StringIO.new)

      refute File.exist?(removable)
      assert File.exist?(kept)
    end
  end

  def test_live_execution_removes_claude_vm_bundles_only
    with_home do |home|
      vm_bundles = File.join(home, "Library", "Application Support", "Claude", "vm_bundles")
      cache = File.join(home, "Library", "Application Support", "Claude", "Cache")

      FileUtils.mkdir_p(vm_bundles)
      FileUtils.mkdir_p(cache)
      File.write(File.join(vm_bundles, "rootfs.img"), "x")
      File.write(File.join(cache, "index"), "keep")

      options = DiskCleanup::Options.parse(["--home=#{home}", "--only=claude"])
      runner = DiskCleanup::Runner.new(options)

      runner.execute(io: StringIO.new)

      refute File.exist?(vm_bundles)
      assert File.exist?(cache)
    end
  end

  def test_map_flag_enables_report_mode
    options = DiskCleanup::Options.parse(["--map", "--top=5"])

    assert_equal true, options.map_only
    assert_equal 5, options.report_limit
  end

  def test_map_path_enables_report_mode_and_expands_path
    with_home do |home|
      options = DiskCleanup::Options.parse(["--home=#{home}", "--map-path=Downloads", "--top=3"])

      assert_equal true, options.map_only
      assert_equal File.join(home, "Downloads"), options.map_path
      assert_equal 3, options.report_limit
    end
  end

  def test_invalid_top_value_raises
    error = assert_raises(ArgumentError) do
      DiskCleanup::Options.parse(["--map", "--top=0"])
    end

    assert_match("--top must be greater than 0", error.message)
  end

  def test_space_report_maps_largest_directories_in_key_areas
    with_home do |home|
      projects_root = File.join(home, "Projects")
      github = File.join(projects_root, "github")
      dotted = File.join(projects_root, "dotted")
      claude = File.join(home, "Library", "Application Support", "Claude")
      cursor = File.join(home, "Library", "Application Support", "Cursor")
      downloads = File.join(home, "Downloads")
      videos = File.join(home, "Videos")

      write_payload(File.join(github, "repo.bin"), 6)
      write_payload(File.join(dotted, "repo.bin"), 2)
      write_payload(File.join(claude, "cache.bin"), 5)
      write_payload(File.join(cursor, "cache.bin"), 1)
      write_payload(File.join(downloads, "movie.bin"), 4)
      write_payload(File.join(videos, "clip.bin"), 3)

      options = DiskCleanup::Options.parse([
        "--home=#{home}",
        "--projects-root=#{projects_root}",
        "--map",
        "--top=2"
      ])

      runner = DiskCleanup::Runner.new(options)
      report = runner.space_report

      assert_equal ["Home", "Projects", "Application Support"], report.map(&:title)

      home_paths = report[0].entries.map(&:path)
      project_paths = report[1].entries.map(&:path)
      app_support_paths = report[2].entries.map(&:path)

      assert_equal [downloads, videos], home_paths
      assert_equal [github, dotted], project_paths
      assert_equal [claude, cursor], app_support_paths
    end
  end

  def test_space_report_for_specific_path_ranks_largest_children
    with_home do |home|
      target = File.join(home, "Library", "Application Support", "Claude")
      projects = File.join(target, "Projects")
      cache = File.join(target, "Cache")
      logs = File.join(target, "Logs")

      write_payload(File.join(projects, "blob.bin"), 7)
      write_payload(File.join(cache, "blob.bin"), 5)
      write_payload(File.join(logs, "blob.bin"), 1)

      options = DiskCleanup::Options.parse([
        "--home=#{home}",
        "--map-path=#{target}",
        "--top=2"
      ])

      runner = DiskCleanup::Runner.new(options)
      report = runner.space_report

      assert_equal ["Path"], report.map(&:title)
      assert_equal [projects, cache], report.first.entries.map(&:path)
    end
  end

  def test_space_report_for_specific_path_includes_files
    with_home do |home|
      target = File.join(home, "Library", "Application Support", "Claude", "vm_bundles", "claudevm.bundle")
      large_file = File.join(target, "disk.img")
      medium_dir = File.join(target, "metadata")
      small_file = File.join(target, "notes.txt")

      write_payload(large_file, 9)
      write_payload(File.join(medium_dir, "blob.bin"), 4)
      write_payload(small_file, 1)

      options = DiskCleanup::Options.parse([
        "--home=#{home}",
        "--map-path=#{target}",
        "--top=3"
      ])

      runner = DiskCleanup::Runner.new(options)
      report = runner.space_report

      assert_equal [large_file, medium_dir, small_file], report.first.entries.map(&:path)
    end
  end

  def test_map_execution_prints_ranked_report
    with_home do |home|
      downloads = File.join(home, "Downloads")
      FileUtils.mkdir_p(downloads)
      File.write(File.join(downloads, "archive.zip"), "x" * 1024)

      options = DiskCleanup::Options.parse(["--home=#{home}", "--map", "--top=1"])
      io = StringIO.new

      DiskCleanup::Runner.new(options).execute(io: io)

      output = io.string
      assert_includes output, "Disk usage map"
      assert_includes output, "Top 1 in Home"
      assert_includes output, downloads
      refute_includes output, "Disk cleanup"
    end
  end

  def test_map_path_execution_prints_targeted_section
    with_home do |home|
      target = File.join(home, "Downloads")
      large = File.join(target, "Large")
      small = File.join(target, "Small")

      write_payload(File.join(large, "blob.bin"), 8)
      write_payload(File.join(small, "blob.bin"), 2)

      options = DiskCleanup::Options.parse(["--home=#{home}", "--map-path=#{target}", "--top=1"])
      io = StringIO.new

      DiskCleanup::Runner.new(options).execute(io: io)

      output = io.string
      assert_includes output, "Disk usage map"
      assert_includes output, "Top 1 in Path"
      assert_includes output, large
      refute_includes output, "Top 1 in Home"
    end
  end

  def test_new_options_default_to_no_age_filter_and_no_force
    options = DiskCleanup::Options.parse([])

    assert_equal 0, options.min_age_days
    assert_equal false, options.force
  end

  def test_min_age_days_skips_downloads_newer_than_the_limit
    with_home do |home|
      downloads = File.join(home, "Downloads")
      old_installer = write_file(File.join(downloads, "old.dmg"))
      recent_installer = write_file(File.join(downloads, "recent.dmg"))
      age_path(old_installer, days: 10)

      options = DiskCleanup::Options.parse([
        "--home=#{home}",
        "--only=downloads",
        "--min-age-days=7",
        "--dry-run"
      ])
      paths = DiskCleanup::Runner.new(options).plan.flat_map(&:paths)

      assert_equal [old_installer], paths
      refute_includes paths, recent_installer
    end
  end

  def test_min_age_days_skips_trash_items_newer_than_the_limit
    with_home do |home|
      trash = File.join(home, ".Trash")
      old_item = write_file(File.join(trash, "old.txt"))
      recent_item = write_file(File.join(trash, "recent.txt"))
      age_path(old_item, days: 30)

      options = DiskCleanup::Options.parse([
        "--home=#{home}",
        "--only=trash",
        "--min-age-days=7",
        "--dry-run"
      ])
      paths = DiskCleanup::Runner.new(options).plan.flat_map(&:paths)

      assert_equal [old_item], paths
      refute_includes paths, recent_item
    end
  end

  def test_negative_min_age_days_raises
    error = assert_raises(ArgumentError) do
      DiskCleanup::Options.parse(["--min-age-days=-1"])
    end

    assert_match("--min-age-days must be zero or greater", error.message)
  end

  def test_paths_in_use_by_a_working_process_are_skipped
    with_home do |home|
      projects_root = File.join(home, "Projects")
      project = File.join(projects_root, "app")
      node_modules = File.join(project, "node_modules")
      FileUtils.mkdir_p(node_modules)

      action = plan_projects_action(home, projects_root, working_directories: [project])

      assert_empty action.paths
      assert_equal [node_modules], action.skipped
    end
  end

  def test_force_removes_paths_that_are_in_use
    with_home do |home|
      projects_root = File.join(home, "Projects")
      project = File.join(projects_root, "app")
      node_modules = File.join(project, "node_modules")
      FileUtils.mkdir_p(node_modules)

      action = plan_projects_action(home, projects_root, working_directories: [project], force: true)

      assert_equal [node_modules], action.paths
      assert_empty action.skipped
    end
  end

  def test_working_directory_inside_the_path_marks_it_in_use
    with_home do |home|
      projects_root = File.join(home, "Projects")
      project = File.join(projects_root, "app")
      node_modules = File.join(project, "node_modules")
      nested = File.join(node_modules, ".vite")
      FileUtils.mkdir_p(nested)

      action = plan_projects_action(home, projects_root, working_directories: [nested])

      assert_empty action.paths
      assert_equal [node_modules], action.skipped
    end
  end

  def test_broad_working_directories_do_not_mark_paths_in_use
    with_home do |home|
      projects_root = File.join(home, "Projects")
      node_modules = File.join(projects_root, "app", "node_modules")
      FileUtils.mkdir_p(node_modules)

      broad = [home, File.join(home, "Desktop"), File.join(home, "Downloads"), projects_root]
      action = plan_projects_action(home, projects_root, working_directories: broad)

      assert_equal [node_modules], action.paths
      assert_empty action.skipped
    end
  end

  def test_real_process_working_directory_marks_project_paths_in_use
    skip "lsof unavailable" unless system("command -v lsof > /dev/null 2>&1")

    with_home do |home|
      projects_root = File.join(home, "Projects")
      project = File.join(projects_root, "app")
      node_modules = File.join(project, "node_modules")
      FileUtils.mkdir_p(node_modules)

      pid = Process.spawn(RbConfig.ruby, "-e", "sleep 20", chdir: project)
      begin
        action = plan_projects_action_until_skipped(home, projects_root, node_modules)

        assert_equal [node_modules], action.skipped
        assert_empty action.paths
      ensure
        Process.kill("TERM", pid)
        Process.wait(pid)
      end
    end
  end

  def test_removal_failures_are_reported_and_do_not_stop_other_categories
    skip "requires directory permissions" if Process.uid.zero?

    with_home do |home|
      downloads = File.join(home, "Downloads")
      FileUtils.mkdir_p(downloads)
      blocked = write_file(File.join(downloads, "blocked.dmg"))

      trash = File.join(home, ".Trash")
      trashed = write_file(File.join(trash, "junk.txt"))

      File.chmod(0o500, downloads)
      begin
        options = DiskCleanup::Options.parse(["--home=#{home}", "--only=downloads,trash"])
        io = StringIO.new

        failures = DiskCleanup::Runner.new(options).execute(io: io)

        assert_equal [blocked], failures
        refute File.exist?(trashed)
        assert_includes io.string, "Failed to remove: 1 item(s)"
        assert_includes io.string, blocked
      ensure
        File.chmod(0o700, downloads)
      end
    end
  end

  def test_dry_run_reports_no_removal_failures
    with_home do |home|
      downloads = File.join(home, "Downloads")
      FileUtils.mkdir_p(downloads)
      blocked = write_file(File.join(downloads, "blocked.dmg"))

      File.chmod(0o500, downloads)
      begin
        options = DiskCleanup::Options.parse(["--home=#{home}", "--only=downloads", "--dry-run"])
        io = StringIO.new

        failures = DiskCleanup::Runner.new(options).execute(io: io)

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
        script = File.expand_path("disk_cleanup.rb", __dir__)
        output, status = Open3.capture2e(RbConfig.ruby, script, "--home=#{home}", "--only=downloads")

        assert_equal 1, status.exitstatus
        assert_includes output, "Failed to remove"
      ensure
        File.chmod(0o700, downloads)
      end
    end
  end

  private

  def plan_projects_action(home, projects_root, working_directories: nil, force: false)
    arguments = ["--home=#{home}", "--projects-root=#{projects_root}", "--only=projects", "--dry-run"]
    arguments << "--force" if force

    options = DiskCleanup::Options.parse(arguments)
    DiskCleanup::Runner.new(options, working_directories: working_directories).plan.first
  end

  def plan_projects_action_until_skipped(home, projects_root, path)
    action = nil

    50.times do
      action = plan_projects_action(home, projects_root)
      break if action.skipped.include?(path)

      sleep 0.1
    end

    action
  end

  def write_file(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "x")
    path
  end

  def age_path(path, days:)
    time = Time.now - (days * 86_400)
    File.utime(time, time, path)
  end

  def write_payload(path, kibibytes)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, "x" * kibibytes * 1024)
  end
end
