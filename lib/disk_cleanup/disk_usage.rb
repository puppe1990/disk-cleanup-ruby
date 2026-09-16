# frozen_string_literal: true

require "shellwords"

begin
  require "sys/filesystem"
rescue LoadError
  # `free_bytes` falls back to df when the gem is missing.
end

module DiskCleanup
  # A path with the number of bytes it occupies.
  MeasuredPath = Struct.new(:path, :bytes, keyword_init: true)

  # Measures paths and free space. Directory walks skip unreadable entries
  # instead of raising, because caches are full of them.
  module DiskUsage
    module_function

    def bytes_for(path)
      return 0 unless File.exist?(path)

      if File.file?(path) || File.symlink?(path)
        File.lstat(path).size
      else
        directory_bytes(path)
      end
    rescue Errno::ENOENT, Errno::EACCES
      0
    end

    def directory_bytes(dir)
      queue = [dir]
      total = 0

      until queue.empty?
        current = queue.pop
        total += entry_bytes(current)
        queue.concat(child_paths(current))
      end

      total
    end

    def free_bytes(path)
      stat = Sys::Filesystem.stat(path)
      stat.block_size * stat.blocks_available
    rescue NameError
      `df -k #{Shellwords.escape(path)}`.lines.last.to_s.split[3].to_i * 1024
    end

    def entry_bytes(path)
      File.lstat(path).size
    rescue Errno::ENOENT, Errno::EACCES, Errno::EPERM
      0
    end

    def child_paths(path)
      return [] unless File.directory?(path) && !File.symlink?(path)

      Dir.children(path).map { |child| File.join(path, child) }
    rescue Errno::ENOENT, Errno::EACCES, Errno::EPERM
      []
    end
  end
end
