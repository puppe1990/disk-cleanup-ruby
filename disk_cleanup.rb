#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/disk_cleanup"

settings = DiskCleanup::Options.parse(ARGV)
failures = DiskCleanup::Runner.new(settings).execute
exit 1 unless failures.empty?
