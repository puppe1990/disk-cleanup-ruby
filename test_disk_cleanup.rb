require "tmpdir"
require "fileutils"
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
      keep_dir = File.join(projects_root, "app3", "src")

      FileUtils.mkdir_p(node_modules)
      FileUtils.mkdir_p(next_dir)
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
      refute_includes paths, keep_dir
    end
  end
end
