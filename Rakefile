require "rubygems"
require "rake/testtask"
require 'spec/rake/spectask'

Rake::TestTask.new do |test|
  test.libs << "test"
  test.test_files = [ "**/test.rb" ]
  test.verbose = true
end

Spec::Rake::SpecTask.new(:spec) do |t|
  desc "Run specs for rake tasks"
  t.spec_opts = ['--options', "\"spec/spec.opts\""]
  t.spec_files = FileList["**/spec.rb"]
end
