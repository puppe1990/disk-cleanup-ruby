# frozen_string_literal: true

require "open3"

module DiskCleanup
  # Decides whether a linked git worktree can be removed without losing work.
  # Only worktrees with no local changes and no commits ahead of their upstream
  # qualify; detached and upstream-less worktrees are left alone.
  class WorktreeGuard
    # Git exports these to hooks, and a leaked GIT_DIR makes `git -C` look at
    # the wrong repository, so every call clears them.
    GIT_ENV = {
      "GIT_DIR" => nil,
      "GIT_WORK_TREE" => nil,
      "GIT_INDEX_FILE" => nil,
      "GIT_OBJECT_DIRECTORY" => nil,
      "GIT_COMMON_DIR" => nil
    }.freeze

    def removable?(path)
      return false unless worktree?(path)

      clean?(path) && pushed?(path)
    end

    private

    def worktree?(path)
      File.file?(File.join(path, ".git"))
    end

    def clean?(path)
      output, status = git(path, "status", "--porcelain")
      status.success? && output.empty?
    end

    def pushed?(path)
      output, status = git(path, "log", "--oneline", "@{upstream}..")
      status.success? && output.empty?
    end

    def git(path, *arguments)
      Open3.capture2e(GIT_ENV, "git", "-C", path, *arguments)
    end
  end
end
