# frozen_string_literal: true

require_relative "../test_helper"

class UsageGuardTest < DiskCleanupTest
  def test_paths_in_use_by_a_working_process_are_skipped
    with_home do |home|
      projects_root = File.join(home, "Projects")
      project = File.join(projects_root, "app")
      node_modules = File.join(project, "node_modules")
      FileUtils.mkdir_p(node_modules)

      action = projects_action(home, projects_root, working_directories: [project])

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

      action = projects_action(home, projects_root, working_directories: [project], force: true)

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

      action = projects_action(home, projects_root, working_directories: [nested])

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
      action = projects_action(home, projects_root, working_directories: broad)

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
        action = projects_action_until_skipped(home, projects_root, node_modules)

        assert_equal [node_modules], action.skipped
        assert_empty action.paths
      ensure
        Process.kill("TERM", pid)
        Process.wait(pid)
      end
    end
  end
end
