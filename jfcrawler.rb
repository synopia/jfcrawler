require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'thread'

TOPICS_PER_PAGE = 20

module Statistic
  class ::Numeric
    def to(unit, places=1)
      units = { :b => 1,
                :kb => 1024**1,
                :mb => 1024**2,
                :gb => 1024**3,
                :tb => 1024**4,
                :pb => 1024**5,
                :eb => 1024**6}
      unitval = units[unit.to_s.downcase.to_sym]
      "#{sprintf("%.#{places}f", self / unitval)} #{unit.to_s.upcase}"
    end # to
  end

  MUTEX = Mutex.new
  def self.add_network(amount)
    MUTEX.synchronize do
      @total_network ||= 0
      @total_network += amount
    end
  end

  def self.network_info
    return '' if @start_time.nil?
    MUTEX.synchronize do
      time_diff = Time.now.to_f - @start_time
      "#{(@total_network.to_f/time_diff.to_f).to(:MB)}/s, total: #{@total_network.to_f.to(:MB)}"
    end
  end

  def self.start
    @start_time = Time.now.to_f
  end
end

class JFCrawler
  HEADER_HASH = {'User-Agent' =>"Ruby/#{RUBY_VERSION}"}

  def initialize(url, opts={})
    @url = url
    @prefix_url = opts[:prefix]
    @use_cache = opts[:cache]==:on
    @time_to_wait = opts[:wait]
    @today = Date.today.strftime('%d.%m.%Y')
    @yesterday = Date.today.prev_day.strftime('%d.%m.%Y')
  end

  def parse_forums( page=nil, &block )
    page ||= open_url( @url )

    rows = page.css("div.page div table.tborder tbody[id*='collapseobj_forumbit_'] tr")

    rows.each_with_index do |row, i|
      tds = row.css('> td')
      link = tds[1].css('div a').first unless tds[1].nil?

      unless link.nil?
        id = i+1
        id = $1.to_i if link['href'] =~ /.*f=([0-9]+).*/
        yield id, link, to_number(tds[3])
      end
    end
  end

  def parse_topics(link, start_page, pages, &block)
    sep = '&'
    sep = '?' if link['href'].end_with? '/'
    url = "#{link['href']}#{sep}page=#{start_page+1}"
    is_start_page = start_page==0
    begin
      page = open_url(url)

      rows = page.css('div.page div table#threadslist.tborder tbody tr')
      start = 1
      if rows.size-1>TOPICS_PER_PAGE && !is_start_page
        start += rows.size-1-TOPICS_PER_PAGE
      end
      unless rows[start..-1].nil?
        rows[start..-1].each_with_index do |row, i|
          tds = row.css('> td')
          link = tds[2].css("a[id*='thread_title_']").first
          unless link.nil?
            id = $1.to_i if link['href'] =~ /.*t=([0-9]+).*/
            id = $1.to_i if link['href'] =~ /.*\/([0-9]+)\-.*/
            yield id, link, to_number(tds[4].css('>a')[0]), to_number(tds[5])
          end
        end
      end
      url = next_page page
      is_start_page = false
      pages -= 1
    end until url.nil? || pages==0
  end

  def parse_posts( link, &block )
    url = "#{link['href']}"
    begin
      page = open_url(url)
      posts = page.css("div[id='posts'] table[class='tborder']")
      posts.each do |post|
        next if post['id'].nil?
        id = post['id'].gsub(/post/, '').to_i
        lines = post.css('> tr')
        date_time = lines[0].css('>td')[0].text.to_s.strip
        author = lines[1].css("a[class='bigusername']").text.to_s.strip
        title = lines[1].css('>td')[1].css('>div')[0].text.to_s.strip
        content = lines[1].css('>td')[1].css('>div')[1].inner_html.to_s.strip
        yield id, author, to_date_time(date_time), title, content
      end
      url = next_page page
    end until url.nil?
  end

  private

  def next_page( page )
    next_page = page.css("a[rel='next']")
    return next_page.first['href'] if next_page.size>0
    nil
  end

  def open_url( url )
    local_filename = get_filename(url)
    if @use_cache && File.exists?(local_filename)
      content = File.open(local_filename).read
    else
      url = "#{@prefix}#{@url+'/' unless url.start_with? 'http://'}#{url}"
      begin
        content = open(url, HEADER_HASH).read
      rescue Exception=>e
        puts "Error #{url}\n#{e}"
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
    Statistic.add_network(content.size)
    Nokogiri::HTML::Document.parse(content)
  end

  def get_filename( url )
    fn = url.gsub(/#{@url}/, '')
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
