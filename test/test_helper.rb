# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "open3"
require "minitest/autorun"

require_relative "../lib/disk_cleanup"

# Base class with the helpers shared by the disk cleanup tests.
class DiskCleanupTest < Minitest::Test
  SCRIPT = File.expand_path("../disk_cleanup.rb", __dir__)

  def with_home(&block)
    Dir.mktmpdir("disk-cleanup-test", &block)
  end

  def parse_options(home, *arguments)
    DiskCleanup::Options.parse(["--home=#{home}", *arguments])
  end

  def runner_for(home, *arguments, working_directories: nil)
    DiskCleanup::Runner.new(parse_options(home, *arguments), working_directories: working_directories)
  end

  def planned_paths(runner)
    runner.plan.flat_map(&:paths)
  end

  def projects_action(home, projects_root, working_directories: nil, force: false)
    arguments = ["--projects-root=#{projects_root}", "--only=projects", "--dry-run"]
    arguments << "--force" if force

    runner_for(home, *arguments, working_directories: working_directories).plan.first
  end

  def projects_action_until_skipped(home, projects_root, path)
    action = nil

    50.times do
      action = projects_action(home, projects_root)
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
    path
  end
end
