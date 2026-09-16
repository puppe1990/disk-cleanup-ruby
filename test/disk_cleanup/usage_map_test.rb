# frozen_string_literal: true

require_relative "../test_helper"

class UsageMapTest < DiskCleanupTest
  def test_maps_largest_directories_in_key_areas
    with_home do |home|
      projects_root = File.join(home, "Projects")
      github = File.join(projects_root, "github")
      dotted = File.join(projects_root, "dotted")
      claude = File.join(home, "Library", "Application Support", "Claude")
      cursor = File.join(home, "Library", "Application Support", "Cursor")
      downloads = File.join(home, "Downloads")
      videos = File.join(home, "Videos")

      write_payload(File.join(github, "repo.bin"), 6)
      write_payload(File.join(dotted, "repo.bin"), 2)
      write_payload(File.join(claude, "cache.bin"), 5)
      write_payload(File.join(cursor, "cache.bin"), 1)
      write_payload(File.join(downloads, "movie.bin"), 4)
      write_payload(File.join(videos, "clip.bin"), 3)

      runner = runner_for(home, "--projects-root=#{projects_root}", "--map", "--top=2")
      report = runner.space_report

      assert_equal ["Home", "Projects", "Application Support"], report.map(&:title)
      assert_equal [downloads, videos], report[0].entries.map(&:path)
      assert_equal [github, dotted], report[1].entries.map(&:path)
      assert_equal [claude, cursor], report[2].entries.map(&:path)
    end
  end

  def test_ranks_largest_children_of_a_specific_path
    with_home do |home|
      target = File.join(home, "Library", "Application Support", "Claude")
      projects = File.join(target, "Projects")
      cache = File.join(target, "Cache")
      logs = File.join(target, "Logs")

      write_payload(File.join(projects, "blob.bin"), 7)
      write_payload(File.join(cache, "blob.bin"), 5)
      write_payload(File.join(logs, "blob.bin"), 1)

      report = runner_for(home, "--map-path=#{target}", "--top=2").space_report

      assert_equal ["Path"], report.map(&:title)
      assert_equal [projects, cache], report.first.entries.map(&:path)
    end
  end

  def test_specific_path_report_includes_files
    with_home do |home|
      target = File.join(home, "Library", "Application Support", "Claude", "vm_bundles", "claudevm.bundle")
      large_file = File.join(target, "disk.img")
      medium_dir = File.join(target, "metadata")
      small_file = File.join(target, "notes.txt")

      write_payload(large_file, 9)
      write_payload(File.join(medium_dir, "blob.bin"), 4)
      write_payload(small_file, 1)

      report = runner_for(home, "--map-path=#{target}", "--top=3").space_report

      assert_equal [large_file, medium_dir, small_file], report.first.entries.map(&:path)
    end
  end

  def test_map_execution_prints_ranked_report
    with_home do |home|
      downloads = File.join(home, "Downloads")
      FileUtils.mkdir_p(downloads)
      File.write(File.join(downloads, "archive.zip"), "x" * 1024)

      io = StringIO.new
      runner_for(home, "--map", "--top=1").execute(io: io)

      assert_includes io.string, "Disk usage map"
      assert_includes io.string, "Top 1 in Home"
      assert_includes io.string, downloads
      refute_includes io.string, "Disk cleanup"
    end
  end

  def test_map_path_execution_prints_targeted_section
    with_home do |home|
      target = File.join(home, "Downloads")
      large = File.join(target, "Large")
      small = File.join(target, "Small")

      write_payload(File.join(large, "blob.bin"), 8)
      write_payload(File.join(small, "blob.bin"), 2)

      io = StringIO.new
      runner_for(home, "--map-path=#{target}", "--top=1").execute(io: io)

      assert_includes io.string, "Disk usage map"
      assert_includes io.string, "Top 1 in Path"
      assert_includes io.string, large
      refute_includes io.string, "Top 1 in Home"
    end
  end
end
