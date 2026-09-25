# frozen_string_literal: true

module DiskCleanup
  # Writes the cleanup summary and the usage map to the console.
  class Reporter
    def initialize(io: $stdout)
      @io = io
      @io.sync = true if @io.respond_to?(:sync=)
    end

    def cleanup_started(dry_run:, free_before:, started_at: Time.now)
      @io.puts "Disk cleanup"
      @io.puts "Started: #{started_at.strftime('%Y-%m-%d %H:%M:%S')}"
      @io.puts "Mode: #{dry_run ? 'dry-run' : 'live'}"
      @io.puts "Free before: #{format_bytes(free_before)}"
    end

    def action_result(action, removed_bytes)
      @io.puts action_line(action, removed_bytes)
    end

    def cleanup_finished(free_after:, removed_total:)
      @io.puts "Free after: #{format_bytes(free_after)}"
      @io.puts "Estimated removed: #{format_bytes(removed_total)}"
    end

    def skipped_actions(actions)
      skipped = actions.flat_map(&:skipped)
      return if skipped.empty?

      @io.puts "Skipped (in use, use --force to remove): #{skipped.size} item(s)"
      skipped.each { |path| @io.puts "  #{path}" }
    end

    def protected_paths(survivors)
      return if survivors.empty?

      @io.puts "Protected by macOS (left alone): #{survivors.size} item(s)"
      survivors.each { |survivor| @io.puts "  #{survivor.path}" }
    end

    def failed_removals(failures)
      return if failures.empty?

      @io.puts "Failed to remove: #{failures.size} item(s)"
      failures.each { |failure| @io.puts "  #{failure}" }
    end

    def usage_map(sections:, limit:)
      @io.puts "Disk usage map"

      sections.each do |section|
        @io.puts "Top #{limit} in #{section.title}"
        print_entries(section.entries)
      end
    end

    private

    def print_entries(entries)
      if entries.empty?
        @io.puts "(no entries found)"
        return
      end

      entries.each { |entry| @io.puts "#{format_bytes(entry.bytes)}\t#{entry.path}" }
    end

    def action_line(action, removed_bytes)
      counts = "#{action.paths.size} item(s), #{format_bytes(removed_bytes)}"
      "[#{action.category}] #{action.label}: #{counts}#{skipped_note(action)}"
    end

    def skipped_note(action)
      return "" if action.skipped.empty?

      ", #{action.skipped.size} skipped (in use)"
    end

    def format_bytes(bytes)
      ByteFormat.format_bytes(bytes)
    end
  end
end
