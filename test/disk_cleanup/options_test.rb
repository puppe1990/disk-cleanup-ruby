# frozen_string_literal: true

require_relative "../test_helper"

class OptionsTest < DiskCleanupTest
  def test_default_categories_include_all_cleanup_groups
    options = DiskCleanup::Options.parse([])

    assert_equal false, options.dry_run
    assert_equal false, options.map_only
    assert_nil options.map_path
    assert_equal 10, options.report_limit
    assert_equal DiskCleanup::Options::CATEGORY_NAMES, options.categories
  end

  def test_projects_root_defaults_under_home
    options = DiskCleanup::Options.parse(["--home=/tmp/example-home"])

    assert_equal "/tmp/example-home/Desktop/Projetos", options.projects_root
  end

  def test_only_and_skip_flags_filter_categories
    options = DiskCleanup::Options.parse(["--only=downloads,projects,caches", "--skip=projects"])

    assert_equal %w[caches downloads], options.categories.sort
  end

  def test_invalid_category_raises
    error = assert_raises(ArgumentError) do
      DiskCleanup::Options.parse(["--only=nope"])
    end

    assert_match("Unknown category", error.message)
  end

  def test_cleanup_options_default_to_no_age_filter_and_no_force
    options = DiskCleanup::Options.parse([])

    assert_equal 0, options.min_age_days
    assert_equal false, options.force
  end

  def test_negative_min_age_days_raises
    error = assert_raises(ArgumentError) do
      DiskCleanup::Options.parse(["--min-age-days=-1"])
    end

    assert_match("--min-age-days must be zero or greater", error.message)
  end

  def test_map_flag_enables_report_mode
    options = DiskCleanup::Options.parse(["--map", "--top=5"])

    assert_equal true, options.map_only
    assert_equal 5, options.report_limit
  end

  def test_map_path_enables_report_mode_and_expands_path
    with_home do |home|
      options = DiskCleanup::Options.parse(["--home=#{home}", "--map-path=Downloads", "--top=3"])

      assert_equal true, options.map_only
      assert_equal File.join(home, "Downloads"), options.map_path
      assert_equal 3, options.report_limit
    end
  end

  def test_invalid_top_value_raises
    error = assert_raises(ArgumentError) do
      DiskCleanup::Options.parse(["--map", "--top=0"])
    end

    assert_match("--top must be greater than 0", error.message)
  end
end
