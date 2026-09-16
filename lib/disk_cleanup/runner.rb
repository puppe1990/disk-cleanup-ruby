# frozen_string_literal: true

module DiskCleanup
  # Ties the pieces together: build the plan, remove it, report the result.
  class Runner
    def initialize(settings, working_directories: nil)
      @settings = settings
      @usage_guard = UsageGuard.new(settings, working_directories: working_directories)
      @removal = Removal.new
    end

    def plan
      Inventory.new(@settings, usage_guard: @usage_guard).actions
    end

    def space_report
      UsageMap.new(@settings).sections
    end

    def execute(io: $stdout)
      return execute_map(io) if @settings.map_only

      reporter = Reporter.new(io: io)
      reporter.cleanup_started(dry_run: @settings.dry_run, free_before: DiskUsage.free_bytes("/"))

      actions = plan
      failures = []
      removed_total = 0

      actions.each do |action|
        failed = @settings.dry_run ? [] : @removal.remove_paths(action.paths)
        failures.concat(failed)

        removed = bytes_removed(action, failed)
        removed_total += removed
        reporter.action_result(action, removed)
      end

      reporter.cleanup_finished(free_after: DiskUsage.free_bytes("/"), removed_total: removed_total)
      reporter.skipped_actions(actions)
      reporter.failed_removals(failures)

      failures
    end

    private

    def execute_map(io)
      Reporter.new(io: io).usage_map(sections: space_report, limit: @settings.report_limit)
      []
    end

    def bytes_removed(action, failures)
      return action.bytes if failures.empty?

      failed_paths = failures.map(&:path)
      action.entries.reject { |entry| failed_paths.include?(entry.path) }.sum(&:bytes)
    end
  end
end
