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

include Curses

TOPICS_PER_PAGE = 20

options = {}

optparse = OptionParser.new do |opts|
  opts.banner = 'Usage: crawl.rb [options] url'
  opts.on( '-p', '--prefix PREFIX_URL', 'URL to prefix each request. Use this when crawling archive websites') do |url|
    options[:prefix] = url
  end
  opts.on( '-s', '--list', 'Lists all forums and their id') do
    options[:list] = true
  end
  opts.on( '-f', '--forum FORUM_ID', Integer, 'Select forum') do |forum_id|
    options[:forum_id] = forum_id
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
  opts.on( '-c', '--cache OPT', [:on, :off], 'Enable/disable using the download cache') do |cache|
    options[:cache] = cache
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
    puts "#{id}\t#{link.child.text}"
  end
  exit
end

init_screen

begin
  setpos(0,0)
  addstr "Crawling #{ARGV.first} #{options[:forum_id]}"
  refresh
  tasks = []
  total_topic_pages = 0
  crawler.parse_forums do |id, link, topics|
    next if !options[:forum_id].nil? && id!=options[:forum_id]
    pages = topics/TOPICS_PER_PAGE + 1
    task = Task.new(id, link, 0, pages, true)
    tasks << task
    total_topic_pages += pages
  end
  topics_per_thread = total_topic_pages / options[:threads] + 1
  setpos(0,0)
  addstr "Crawling #{ARGV.first} #{options[:forum_id]} (total topic pages=#{total_topic_pages}, topics_per_thread=#{topics_per_thread})"
  refresh
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
      total_topics = thread_tasks.inject(0){|sum, t| sum+(t.limit*TOPICS_PER_PAGE)}
      count = 0.0
      thread_tasks.each do |task|
        setpos(i+2, 14)
        addstr "#{task}                                 "
        refresh
        task.do_work(crawler) do
          count += 1.0
          progress = count / total_topics
          progress_bar = (progress * 10).to_i
          setpos(i+2, 0)
          addstr "[#{'*'*progress_bar}#{' '*(10-progress_bar)}]  "
          refresh
        end
        setpos(i+2, 14)
        addstr 'done'
        refresh
      end
    end
  end
  threads.each do |t|
    t.join
  end
rescue Exception=>e
    puts e
ensure
  close_screen
end