require 'benchmark'
require 'zip/zip'
require './jfcrawler'

class Task
  attr_reader :limit

  def initialize( forum_id, forum_link, start_page, limit, last )
    @forum_link = forum_link
    @forum_id = forum_id
    @start_page = start_page
    @limit = limit
    @subdir = "f_#{@forum_id}"
    @last = last
  end

  def do_work(crawler, &block)
    crawler.parse_topics(@forum_link, @start_page, @last ? -1 : @limit) do |topic_id, link, replies, hits|
      Dir.mkdir(@subdir) unless Dir.exists?(@subdir)
      f = File.new "#{@subdir}/t_#{topic_id}.zip", "w"
      Zip::ZipOutputStream.open(f.path) do |z|
        crawler.parse_posts(link) do |post_id, author, date_time, title, content|
          z.put_next_entry("p_#{post_id}.txt")
          z.write "{\n   author='#{author},'\n"
          z.write "   time='#{date_time.xmlschema}',\n"
          z.write "   title='#{title}',\n"
          z.write "<<<<\n"
          z.write content
          z.write "\n>>>>\n}"
          yield
        end
      end
    end
  end

  def split(new_limit)
    new_task = Task.new @forum_id, @forum_link, @start_page+new_limit, @limit-new_limit, true
    @limit = new_limit
    @last = false
    [self, new_task]
  end

  def to_s
    "#{@forum_id} #{@forum_link.child.text} #{@start_page} #{@limit} #{@last}"
  end
end
