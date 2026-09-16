# frozen_string_literal: true

module DiskCleanup
  # Filesystem listing helpers shared by the cleanup inventory and the usage map.
  module PathListing
    module_function

    def existing_children(dir)
      return [] unless Dir.exist?(dir)

      safe_glob(File.join(dir, "*"), File::FNM_DOTMATCH)
        .reject { |path| %w[. ..].include?(File.basename(path)) }
    end

    def directories(dir)
      existing_children(dir).select { |path| File.directory?(path) }
    end

    def safe_glob(pattern, flags = 0)
      Dir.glob(pattern, flags)
    rescue Errno::ENOENT, Errno::EACCES, Errno::EPERM
      []
    end
  end
end
