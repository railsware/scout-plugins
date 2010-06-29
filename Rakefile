require "rake/testtask"
require "rubygems"
require 'spec/rake/spectask'

Rake::TestTask.new do |test|
  test.libs << "test"
  test.test_files = [ "**/test.rb" ]
  test.verbose = true
end

namespace :spec do
  desc "Run specs for rake tasks"
  Spec::Rake::SpecTask.new(:raketasks) do |t|
    t.spec_opts = ['--options', "\"spec/spec.opts\""]
    t.spec_files = FileList["**/spec.rb"]
  end
end
