require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'optparse'
require 'benchmark'
require 'zip/zip'
require 'pp'
require "curses"
require './jfcrawler'
require './workers'
require './display'


options = {}

optparse = OptionParser.new do |opts|
  opts.banner = 'Usage: crawl.rb [options] url'
  opts.on( '-p', '--prefix PREFIX_URL', 'URL to prefix each request. Use this when crawling archive websites') do |url|
    options[:prefix] = url
  end
  opts.on( '-s', '--list', 'Lists all forums and their id') do
    options[:list] = true
  end
  opts.on( '-f', '--forum id1,id2,id3,..', Array, 'Select forum') do |forum_ids|
    options[:forum_ids] = forum_ids
  end
  options[:threads] = 1
  opts.on( '-t', '--threads THREAD', Integer, 'Number of threads to use') do |threads|
    options[:threads] = threads
  end
  options[:wait] = 1
  opts.on( '-w', '--wait SECONDS', Float, 'Time to wait between download requests') do |time|
    options[:wait] = time
  end
  options[:cache] = :off
  opts.on( '-c', '--cache', 'Enable the download cache') do
    options[:cache] = :on
  end
  options[:display] = :curse
  opts.on( '-r', '--nocurse', 'Disable curse gui') do
    options[:display] = :simple
  end
  opts.on( '-h', '--help', 'Display this screen' ) do
    puts opts
    exit
  end
end

begin
  optparse.parse!
rescue Exception=>e
  puts e
  puts optparse
  exit
end

if ARGV.empty?
  puts optparse
  exit
end


crawler = JFCrawler.new ARGV.first, options

if options[:cache] && !Dir.exists?('cache')
  Dir.mkdir('cache')
end
if options[:list]
  crawler.parse_forums do |id, link, topics|
    puts "#{id}\t#{link.child.text} (#{topics})"
  end
  exit
end


begin
  display = options[:display]==:curse && CursesDisplay.available? ? CursesDisplay.new : SimpleDisplay.new
  display.start 'Getting forums... '
  tasks = []
  total_topics = 0
  Statistic.start
  crawler.parse_forums do |id, link, topics|
    next if !options[:forum_ids].nil? && !options[:forum_ids].include?(id.to_s)
    display.info 0, link.child.text
    task = Task.new(id, link, 0, topics, true)
    tasks << task
    total_topics += topics
  end
  topics_per_thread = total_topics / options[:threads] + 1
  topics_per_thread = TOPICS_PER_PAGE if topics_per_thread<TOPICS_PER_PAGE

  display.start "#{tasks.size} forums found with a total of #{total_topics} topics."

  threads = []
  options[:threads].times do |i|
    thread_tasks = []
    topics_remain = topics_per_thread
    while topics_remain>0 && !tasks.empty?
      task = tasks.shift
      if task.limit<topics_remain
        topics_remain -= task.limit
        thread_tasks << task
      else
        split = task.split topics_remain
        thread_tasks << split[0]
        tasks << split[1]
        topics_remain = 0
      end
    end
    threads << Thread.new do
      topics = thread_tasks.inject(0){|sum, t| sum+t.limit}
      count = 0.0
      thread_tasks.each do |task|
        task.do_work(i, crawler, display) do
          display.info i, task.to_s
          count += 1.0
          progress = count / topics
          display.progress i, progress
        end
      end
      display.progress i, 1
      display.status i, 'done'
    end
  end
  display.start "Scanning #{total_topics} topics with #{options[:threads]} threads..."

  threads.each do |t|
    t.join
  end
  display.render

rescue Exception=>e
  display.finish 'bye'
  puts e
ensure
  #display.finish 'bye'
end

puts Statistic.network_info