# frozen_string_literal: true

module DiskCleanup
  # Renders a byte count in binary units (B, KiB, MiB, ...).
  module ByteFormat
    module_function

    def format_bytes(bytes)
      units = %w[B KiB MiB GiB TiB]
      value = bytes.to_f
      unit = units.shift

      while value >= 1024 && !units.empty?
        value /= 1024.0
        unit = units.shift
      end

      if value >= 10 || unit == "B"
        format("%<value>.0f %<unit>s", value: value, unit: unit)
      else
        format("%<value>.1f %<unit>s", value: value, unit: unit)
      end
    end
  end
end
