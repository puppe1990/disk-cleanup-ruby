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

  def test_project_cleanup_matches_next_dev_and_python_virtualenvs
    with_home do |home|
      projects_root = File.join(home, "Projects")
      next_dev = File.join(projects_root, "app", ".next-dev")
      next_dev_port = File.join(projects_root, "app", ".next-dev-3001")
      venv = File.join(projects_root, "py", ".venv")
      named_venv = File.join(projects_root, "py2", "venv")
      keep_nextauth = File.join(projects_root, "app", ".nextauth")

      [next_dev, next_dev_port, venv, named_venv, keep_nextauth].each do |path|
        FileUtils.mkdir_p(path)
      end

      paths = planned_paths(runner_for(home, "--projects-root=#{projects_root}", "--only=projects", "--dry-run"))

      assert_includes paths, next_dev
      assert_includes paths, next_dev_port
      assert_includes paths, venv
      assert_includes paths, named_venv
      refute_includes paths, keep_nextauth
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
      npm_npx = File.join(home, ".npm", "_npx")
      generic_cache = File.join(home, ".cache")
      bun_cache = File.join(home, ".bun", "install", "cache")
      pnpm_store = File.join(home, "Library", "pnpm", "store")
      cargo_registry = File.join(home, ".cargo", "registry")

      [library_cache_child, npm_cache, npm_npx, generic_cache, bun_cache, pnpm_store, cargo_registry].each do |path|
        FileUtils.mkdir_p(path)
        File.write(File.join(path, "payload"), "x")
      end

      paths = planned_paths(runner_for(home, "--only=caches", "--dry-run"))

      assert_includes paths, library_cache_child
      assert_includes paths, npm_cache
      assert_includes paths, npm_npx
      assert_includes paths, generic_cache
      assert_includes paths, bun_cache
      assert_includes paths, pnpm_store
      assert_includes paths, cargo_registry
    end
  end

  def test_cache_cleanup_skips_apple_system_caches
    with_home do |home|
      caches = File.join(home, "Library", "Caches")
      apple = File.join(caches, "com.apple.Safari")
      cloudkit = File.join(caches, "CloudKit")
      family = File.join(caches, "FamilyCircle")
      user_cache = File.join(caches, "com.test.app")

      [apple, cloudkit, family, user_cache].each do |path|
        FileUtils.mkdir_p(path)
        File.write(File.join(path, "payload"), "x")
      end

      paths = planned_paths(runner_for(home, "--only=caches", "--dry-run"))

      assert_includes paths, user_cache
      refute_includes paths, apple
      refute_includes paths, cloudkit
      refute_includes paths, family
    end
  end

  def test_cache_cleanup_skips_unwritable_library_caches
    skip "requires directory permissions" if Process.uid.zero?

    with_home do |home|
      locked = File.join(home, "Library", "Caches", "locked.app")
      FileUtils.mkdir_p(locked)
      File.write(File.join(locked, "payload"), "x")
      File.chmod(0o500, locked)

      begin
        paths = planned_paths(runner_for(home, "--only=caches", "--dry-run"))

        refute_includes paths, locked
      ensure
        File.chmod(0o700, locked)
      end
    end
  end

  def test_docker_cleanup_collects_known_docker_directories
    with_home do |home|
      docker_paths = [
        File.join(home, "Library", "Containers", "com.docker.docker"),
        File.join(home, "Library", "Application Support", "Docker"),
        File.join(home, "Library", "Application Support", "Docker Desktop"),
        File.join(home, ".colima")
      ]

      docker_paths.each do |path|
        FileUtils.mkdir_p(path)
        File.write(File.join(path, "state.json"), "{}")
      end

      paths = planned_paths(runner_for(home, "--only=docker", "--dry-run"))

      assert_equal docker_paths.sort, paths.sort
    end
  end

  def test_claude_cleanup_collects_vm_bundles_cache_and_code_vm
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

      paths = planned_paths(runner_for(home, "--only=claude", "--dry-run"))

      assert_equal [cache, code_vm, vm_bundles].sort, paths.sort
      refute_includes paths, local_storage
    end
  end
end
