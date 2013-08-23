#!/usr/bin/env ruby

require 'fileutils'
require 'date'
require 'active_support/core_ext'

# contains delete-only keys of the form xyz.cleanup.key
KEYDIR = "/root/.tarsnap"

# tarsnap cache base directory
CACHE_DIR = "/tmp/tarsnap/cache"

# I do daily backups, and I want to keep the most recent 7 of thos, plus weekly
# backups for the last 12 weeks
KEEP = {
  weekly: 12,
  daily: 7
}

# My servers all have write-only keys, therefore this script is run from a
# desktop machine. That's why I do 'tarsnap --fsck' before each cleanup run to
# bring tarsnap's cache up to date.
#
# Usage:
# Dry run: bundle exec tarsnap-cleanup.rb
# Really delete: bundle exec tarsnap-cleanup.rb really
Tarsnap = Struct.new(:key, :cache_dir) do

  def cleanup
    puts "cleaning up #{basename}"
    update_cache
    files_by_date = list_archives.map do |file|
      if file =~ /(\d{4})-(\d{2})-(\d{2})$/
        date = Time.new $1.to_i, $2.to_i, $3.to_i
        [file, date]
      else
        STDERR.puts "don't know what to do with #{file}"
        nil
      end
    end.compact.sort{|a,b| a[1] <=> b[1]}

    oldest = files_by_date[0][1]

    # keep n most recent daily backups
    if files_by_date.size < KEEP[:daily]
      puts "nothing to do"
      return
    end
    files_by_date = files_by_date[0..(files_by_date.size - KEEP[:daily] - 1)]

    # compile list of valid weekly backup dates
    weekly_backups = [oldest]
    while weekly_backups.last < KEEP[:daily].days.ago
      weekly_backups << weekly_backups.last + 1.week
    end

    # keep n most recent weekly backups
    if weekly_backups.size > KEEP[:weekly]
      weekly_backups = weekly_backups[-1*KEEP[:weekly]..-1]
    end
    files_by_date.reject!{|name,date| weekly_backups.include?(date)}

    # delete them!
    files_by_date.each do |name, date|
      delete_archive name
    end
  end

  def list_archives
    tarsnap('--list-archives').split("\n").map(&:strip)
  end

  def delete_archive(name)
    puts "deleting #{name}"
    tarsnap '-d', '-f', name if ARGV[0] == 'really'
  end

  def key
    self[:key]
  end

  def cache_dir
    File.join self[:cache_dir], basename
  end

  private

  def basename
    @basename ||= if key =~ %r{/([^/]+)\.cleanup}
      $1
    else
      raise "could not determine basename of #{key}"
    end
  end

  def update_cache
    FileUtils.mkdir_p cache_dir
    tarsnap '--fsck'
  end

  def tarsnap(*args)
    `tarsnap --cachedir #{cache_dir} --keyfile #{key} #{args.join(' ')}`
  end

end

Dir["#{KEYDIR}/**/*cleanup.key"].each do |key|
  Tarsnap.new(key, CACHE_DIR).cleanup
end

