require 'benchmark'
require 'zip/zip'
require './jfcrawler'

class Task
  attr_reader :limit

  def initialize( forum_id, forum_link, start_topic, limit, last )
    @forum_link = forum_link
    @forum_id = forum_id
    @start_topic = start_topic
    @limit = limit
    @subdir = "f_#{@forum_id}"
    @last = last
  end

  def do_work(tid, crawler, display, &block)
    start_page = @start_topic/TOPICS_PER_PAGE
    if @last
      limit = -1
    else
      limit = @limit / TOPICS_PER_PAGE
    end
    crawler.parse_topics(@forum_link, start_page, limit) do |topic_id, link, replies, hits|
      yield
      Dir.mkdir(@subdir) unless Dir.exists?(@subdir)
      f = File.new "#{@subdir}/t_#{topic_id}.zip", "w"
      Zip::ZipOutputStream.open(f.path) do |z|
        count = 0
        crawler.parse_posts(link) do |post_id, author, date_time, title, content|
          count += 1
          display.info2 tid, "#{link.text} (#{count}/#{replies})"
          z.put_next_entry("p_#{post_id}.txt")
          z.write "{\n   author='#{author},'\n"
          z.write "   time='#{date_time.xmlschema}',\n"
          z.write "   title='#{title}',\n"
          z.write "<<<<\n"
          z.write content
          z.write "\n>>>>\n}"
        end
        display.info2 tid, ""
      end
    end
  end

  def split(new_limit)
    start_topic = ((@start_topic+new_limit)/TOPICS_PER_PAGE)*TOPICS_PER_PAGE
    new_task = Task.new @forum_id, @forum_link, start_topic, @limit-new_limit, true
    @limit = new_limit
    @last = false
    [self, new_task]
  end

  def to_s
    "#{@forum_link.child.text} (#{@start_topic/TOPICS_PER_PAGE}-#{(@start_topic+@limit)/TOPICS_PER_PAGE})"
  end
end
