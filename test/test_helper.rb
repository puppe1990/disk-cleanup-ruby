# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "open3"
require "minitest/autorun"

require_relative "../lib/disk_cleanup"

# Stands in for FileUtils when removal must be refused the way macOS protects
# app containers: paths stay in place and the direct attempt raises EPERM.
class RefusingFileUtils
  def initialize(error = Errno::EPERM)
    @error = error
  end

  def rm_rf(_path, **_options)
    nil
  end

  def remove_entry(_path)
    raise @error
  end
end

# Stands in for the worktree guard so planner tests do not need real git
# repositories.
class StubWorktreeGuard
  def initialize(removable)
    @removable = removable
  end

  def removable?(path)
    @removable.include?(path)
  end
end

# Base class with the helpers shared by the disk cleanup tests.
class DiskCleanupTest < Minitest::Test
  SCRIPT = File.expand_path("../disk_cleanup.rb", __dir__)

  def with_home(&block)
    Dir.mktmpdir("disk-cleanup-test", &block)
  end

  def parse_options(home, *arguments)
    DiskCleanup::Options.parse(["--home=#{home}", *arguments])
  end

  # Tests are hermetic by default: pass `working_directories: nil` only when a
  # test exercises the lsof lookup against real processes.
  def runner_for(home, *arguments, working_directories: [], removal: nil)
    DiskCleanup::Runner.new(
      parse_options(home, *arguments),
      working_directories: working_directories,
      removal: removal
    )
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

  # Builds a repository with a bare origin so worktree guard tests can push.
  def create_git_repo(home)
    origin = File.join(home, "origin.git")
    repo = File.join(home, "repo")
    run_git("init", "--bare", "--initial-branch=main", origin)
    run_git("init", "--initial-branch=main", repo)
    File.write(File.join(repo, "README.md"), "x")
    run_git("-C", repo, "add", "README.md")
    run_git("-C", repo, "-c", "user.name=test", "-c", "user.email=test@example.com", "commit", "-m", "init")
    run_git("-C", repo, "remote", "add", "origin", origin)
    run_git("-C", repo, "push", "-u", "origin", "main")
    repo
  end

  # Adds a worktree whose branch is already pushed to origin.
  def add_worktree(repo, path, branch)
    run_git("-C", repo, "worktree", "add", "-b", branch, path)
    run_git("-C", path, "push", "-u", "origin", branch)
    path
  end

  def run_git(*arguments)
    env = DiskCleanup::WorktreeGuard::GIT_ENV
    system(env, "git", *arguments, out: File::NULL, err: File::NULL) || raise("git failed: #{arguments.join(' ')}")
  end
end
