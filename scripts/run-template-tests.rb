#!/usr/bin/env ruby

# Works with 3.4.4, require as minimum
if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3.4.4')
  puts "********\n******** WARNING: Ruby template works well with Ruby version = 3.4.4, please upgrade.\n********"
end
Dir.chdir "#{__dir__}/.."
system "gem install bundle"
system  "bundle install"
system  "bundle exec rspec spec"
