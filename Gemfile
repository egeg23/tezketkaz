source "https://rubygems.org"

# Fastlane drives the release pipeline (Android supply, iOS deliver, gym,
# match, pilot). Pin a major range so security patches land automatically
# without surprise breaking changes in a CI run.
gem "fastlane", "~> 2.225"

# CocoaPods is required when building the iOS workspace. Kept in the same
# Gemfile so a single `bundle install` on the macOS runner brings up both
# toolchains.
gem "cocoapods", "~> 1.16"

# Pull in fastlane plugins declared by the Pluginfile loader. The file is
# always present (even if empty) so this eval_gemfile guard is more about
# allowing the file to be deleted than guarding against absence.
plugins_path = File.join(File.dirname(__FILE__), "fastlane", "Pluginfile")
eval_gemfile(plugins_path) if File.exist?(plugins_path)
