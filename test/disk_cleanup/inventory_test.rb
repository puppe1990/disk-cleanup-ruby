# frozen_string_literal: true

require_relative "../test_helper"

class InventoryTest < DiskCleanupTest
  def test_download_cleanup_matches_supported_extensions
    with_home do |home|
      downloads = File.join(home, "Downloads")
      FileUtils.mkdir_p(downloads)

      removable = %w[a.zip b.dmg c.pkg d.iso].map { |name| write_file(File.join(downloads, name)) }
      kept = write_file(File.join(downloads, "keep.mp4"))

      paths = planned_paths(runner_for(home, "--only=downloads", "--dry-run"))

      assert_equal removable.sort, paths.sort
      refute_includes paths, kept
    end
  end

  def test_min_age_days_skips_downloads_newer_than_the_limit
    with_home do |home|
      downloads = File.join(home, "Downloads")
      old_installer = write_file(File.join(downloads, "old.dmg"))
      recent_installer = write_file(File.join(downloads, "recent.dmg"))
      age_path(old_installer, days: 10)

      paths = planned_paths(runner_for(home, "--only=downloads", "--min-age-days=7", "--dry-run"))

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

      paths = planned_paths(runner_for(home, "--only=trash", "--min-age-days=7", "--dry-run"))

      assert_equal [old_item], paths
      refute_includes paths, recent_item
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

      [node_modules, next_dir, rust_target, output_directory, zig_cache, elixir_build, deps, keep_dir].each do |path|
        FileUtils.mkdir_p(path)
      end

      paths = planned_paths(runner_for(home, "--projects-root=#{projects_root}", "--only=projects", "--dry-run"))

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

      [netlify_cache, tmp_dir, build_dir, cache_dir].each { |path| FileUtils.mkdir_p(path) }

      paths = planned_paths(runner_for(home, "--projects-root=#{projects_root}", "--only=projects", "--dry-run"))

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

      paths = planned_paths(runner_for(home, "--only=caches", "--dry-run"))

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

      paths = planned_paths(runner_for(home, "--only=docker", "--dry-run"))

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

      paths = planned_paths(runner_for(home, "--only=claude", "--dry-run"))

      assert_equal [vm_bundles], paths
      refute_includes paths, cache
    end
  end
end
