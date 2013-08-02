require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'optparse'
require 'benchmark'
require 'zip/zip'

class JFCrawler
  HEADER_HASH = {"User-Agent"=>"Ruby/#{RUBY_VERSION}"}

  def initialize(url, opts={})
    @url = url
    @baseurl = "http://#{url.split('/')[2]}"
    @use_cache = opts[:cache]==:on
    @time_to_wait = opts[:wait]
    @today = Date.today.strftime("%d.%m.%Y")
    @yesterday = Date.today.prev_day.strftime("%d.%m.%Y")
  end

  def parse_forums( &block )
    page = open_url( @url )

    rows = page.css("div.page div table.tborder tbody[id*='collapseobj_forumbit_'] tr")

    rows.each do |row|
      tds = row.css('> td')
      link = tds[1].css('div a').first unless tds[1].nil?

      if link.nil?
        nil
      else
        link['href'] =~ /.*f=([0-9]+).*/
        yield $1.to_i, link, to_number(tds[3])
      end
    end
  end

  def parse_topics(link, start_page, pages, &block)
    url = "#{@baseurl}/#{link['href']}"
    begin
      page = open_url(url)
      rows = page.css('div.page div table#threadslist.tborder tbody tr')

      if rows[1..-1].nil?
        puts "ERROR: #{url}"
      else
        rows[1..-1].each do |row|
          tds = row.css('> td')
          link = tds[2].css("a[id*='thread_title_']").first
          if link.nil?
            nil
          else
            link['href'] =~ /.*t=([0-9]+).*/
            yield $1.to_i, link, to_number(tds[4].css('>a')[0]), to_number(tds[5])
          end
        end
      end

      next_page = page.css("a[rel='next']")
      url = @baseurl+'/'+next_page.first['href'] if next_page.size>0
      pages -= 1
    end until next_page.size==0 || pages==0
  end

  def parse_posts( link, &block )
    url = "#{@baseurl}/#{link['href']}"
    begin
      page = open_url(url)
      posts = page.css("div[id='posts'] table[class='tborder']")
      posts.each do |post|
        id = post['id'].gsub(/post/, '').to_i
        lines = post.css('> tr')
        date_time = lines[0].css('>td')[0].text.to_s.strip
        author = lines[1].css("a[class='bigusername']").text.to_s.strip
        title = lines[1].css('>td')[1].css('>div')[0].text.to_s.strip
        content = lines[1].css('>td')[1].css('>div')[1].inner_html.to_s.strip
        yield id, author, to_date_time(date_time), title, content
      end
      next_page = page.css("a[rel='next']")
      url = @baseurl+'/'+next_page.first['href'] unless next_page.size==0
    end until next_page.size==0
  end

  private

  def open_url( url )
    local_filename = get_filename(url)
    if @use_cache && File.exists?(local_filename)
      content = File.open(local_filename)
    else
      puts "Fetching #{url}..."
      begin
        content = open(url, HEADER_HASH).read
      rescue Exception=>e
        puts "Error: #{e}"
        sleep 5
      else
        if @use_cache
          File.open(local_filename, 'w') do |file|
            file.write(content)
          end
        end
      ensure
        sleep @time_to_wait
      end
    end
    Nokogiri::HTML(content)
  end

  def get_filename( url )
    fn = url.gsub(/#{@baseurl}/, '')
    fn[-1]='' if fn[-1]=='/'
    fn.gsub!(/s=[a-z0-9]+/, '')
    fn.gsub!(/[\/\?=&]/, '_')
    fn = 'index.html' if fn==''
    fn = 'cache/'+fn
    fn
  end

  def to_number( arg )
    if !arg.nil? && !arg.child.nil?
      arg.child.to_s.delete('.').to_i
    else
      0
    end
  end

  def to_date_time( arg )
    arg = arg.gsub(/Heute/, @today).gsub(/Gestern/, @yesterday)
    DateTime.strptime(arg, '%d.%m.%Y, %H:%M')
  end
end

options = {}

optparse = OptionParser.new do |opts|
  opts.banner = 'Usage: crawl.rb [options] url'
  opts.on( '-f', '--forum FORUM_ID', Integer, 'Select forum') do |forum_id|
    options[:forum_id] = forum_id
  end
  options[:start_page] = 1
  opts.on( '-s', '--start START_PAGE', Integer, 'Start page in forum to crawl (counting starts at 1)') do |start_page|
    options[:start_page] = start_page
  end
  options[:limit] = 1
  opts.on( '-l', '--limit LIMIT', Integer, 'Maximum number of pages to crawl') do |limit|
    options[:pages] = limit
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
rescue
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

puts "Crawling #{ARGV.first} #{options[:forum_id]} (#{options[:start_page]} - #{options[:pages]})"
threads = []
Benchmark.bm do |x|
  x.report do
    crawler.parse_forums do |id, link, topics|
      next if !options[:forum_id].nil? && id!=options[:forum_id]
      threads << Thread.new do
        Dir.mkdir("f_#{id}") unless Dir.exists?("f_#{id}")
        crawler.parse_topics( link, options[:start_page], options[:pages] ) do |topic_id, link, replies, hits|
          puts "Topic #{topic_id} #{replies} #{hits}"
          f = File.new "f_#{id}/t_#{topic_id}.zip", "w"
          Zip::ZipOutputStream.open(f.path) do |z|
            crawler.parse_posts( link ) do |post_id, author, date_time, title, content|
              z.put_next_entry("p_#{post_id}.txt")
              z.write "{\n   author='#{author},'\n"
              z.write "   time='#{date_time.xmlschema}',\n"
              z.write "   title='#{title}',\n"
              z.write "<<<<\n"
              z.write content
              z.write "\n>>>>\n}"
            end
          end
        end
      end
    end
    threads.each do |t|
      t.join
    end
  end
end
