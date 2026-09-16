# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |task|
  task.libs << "lib"
  task.test_files = FileList["test/**/*_test.rb"]
end

desc "Lint the Ruby sources"
task :lint do
  sh "rubocop"
end

task default: %i[lint test]
