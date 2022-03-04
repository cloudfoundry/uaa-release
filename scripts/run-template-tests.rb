#!/usr/bin/env ruby

# Failed with 3.0.3, not sure why
if Gem::Version.new(RUBY_VERSION) > Gem::Version.new('3.0.2')
  puts "********\n******** WARNING: Ruby template tests might not be compatible with Ruby version > 3.0.2\n********"
end
Dir.chdir "#{__dir__}/.."
system "gem install bundle"
system  "bundle install"
system  "bundle exec rspec spec"
