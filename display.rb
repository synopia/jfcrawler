require "curses"

class Display
  def initialize
    @tasks = {}
    Thread.new do
      until self.abort?
        self.render
        sleep(0.1)
      end
      exit
    end
  end

  def progress( id, value )
    @tasks[id] ||= {}
    @tasks[id][:progress] = value
  end

  def status( id, value )
    @tasks[id] ||= {}
    @tasks[id][:status] = value
  end

  def info( id, msg )
    @tasks[id] ||= {}
    @tasks[id][:info] = msg
  end
  def info2( id, msg )
    @tasks[id] ||= {}
    @tasks[id][:info2] = msg
  end
end

class SimpleDisplay < Display
  def start(msg)
    puts msg
  end

  def render
    text = @tasks.each.collect do |id, task|
      if !task[:status].nil?
        "[#{task[:status]}]"
      elsif !task[:progress].nil?
        "[#{'%03d'%((100*task[:progress]).to_i)}]"
      else
        '[    ]'
      end
    end.join(' ')
    print "#{text}\r"
  end
  def finish(msg)
    puts '\n'
    puts msg
  end
  def abort?
    false
  end
end

class CursesDisplay < Display
  def initialize
    Curses.init_screen
    Curses.stdscr.nodelay = true
    Curses.noecho
    super
  end

  def self.available?
    $stdin.isatty && $stdout.isatty
  end

  def start(msg)
    @msg = msg
    self.render
  end

  def render
    Curses.clear
    Curses.setpos(0,0)
    Curses.addstr(@msg)
    @tasks.each do |id, task|
      progress = ((task[:progress]||0) * 10).to_i
      progress = 0 if progress<0
      progress = 10 if progress>10
      Curses.setpos id+2,0
      Curses.addstr "[#{'*'*progress}#{' '*(10-progress)}]  #{task[:status].nil? ? '    ' : task[:status]}  #{task[:info]}"
      Curses.setpos id+2,60
      Curses.addstr task[:info2] unless task[:info2].nil?
    end
    unless @tasks.nil?
      Curses.setpos 3+@tasks.size, 0
      Curses.addstr "Stats: #{Statistic.network_info}"
    end
    Curses.refresh
  end

  def finish(msg)
    Curses.close_screen
    puts msg
  end

  def abort?
    Curses.stdscr.getch=='q'
  end
end

