# frozen_string_literal: true

require_relative "../test_helper"

class WorktreeGuardTest < DiskCleanupTest
  def test_worktrees_with_pushed_commits_and_no_changes_are_removable
    with_home do |home|
      repo = create_git_repo(home)
      worktree = add_worktree(repo, File.join(home, "wt"), "fix/pushed")

      assert DiskCleanup::WorktreeGuard.new.removable?(worktree)
    end
  end

  def test_worktrees_with_uncommitted_changes_are_kept
    with_home do |home|
      repo = create_git_repo(home)
      worktree = add_worktree(repo, File.join(home, "wt"), "fix/dirty")
      File.write(File.join(worktree, "notes.txt"), "x")

      refute DiskCleanup::WorktreeGuard.new.removable?(worktree)
    end
  end

  def test_worktrees_with_unpushed_commits_are_kept
    with_home do |home|
      repo = create_git_repo(home)
      worktree = add_worktree(repo, File.join(home, "wt"), "fix/ahead")
      File.write(File.join(worktree, "more.txt"), "x")
      run_git("-C", worktree, "add", "more.txt")
      run_git("-C", worktree, "-c", "user.name=test", "-c", "user.email=test@example.com", "commit", "-m", "more")

      refute DiskCleanup::WorktreeGuard.new.removable?(worktree)
    end
  end

  def test_plain_directories_are_kept
    with_home do |home|
      path = File.join(home, "plain")
      FileUtils.mkdir_p(path)

      refute DiskCleanup::WorktreeGuard.new.removable?(path)
    end
  end
end
