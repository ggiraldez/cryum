require "http/headers"
require "http/client"

require "gobject/g_lib"
require "gobject/gdk"
require "gobject/gtk"


class Brium
  def initialize
    @access_token = File.read("#{ENV["HOME"]}/.config/brium/.access_token").strip
  end

  def send_message(message)
    headers = HTTP::Headers{"Authorization" => "Bearer #{@access_token}"}

    HTTP::Client.post "https://brium.me/api/messages", headers, body: message do |response|
      if response.status.ok?
        response.body_io.gets_to_end
      else
        "Error: #{response.status_message}"
      end
    end
  end
end

class CryumWindow < Gtk::ApplicationWindow
  def self.new(app : Gtk::Application)
    super
  end

  def initialize(ptr)
    super(ptr)

    self.border_width = 20
    self.window_position = Gtk::WindowPosition::CENTER_ALWAYS
    self.keep_above = true
    self.title = "Cryum"
    self.add_events Gdk::EventMask::KEY_PRESS_MASK.to_i
    self.set_default_size 500, 500

    self.on_key_press_event do |window, event|
      if event.keyval == Gdk::KEY_Escape
        self.destroy
        true
      else
        false
      end
    end

    create_ui
  end

  getter! text_buffer : Gtk::TextBuffer
  getter! text_view : Gtk::TextView
  getter! end_mark : Gtk::TextMark

  @scroll_view : Gtk::ScrolledWindow?

  def create_ui
    box = Gtk::Box.new(:vertical, spacing: 2)

    scroll_view = Gtk::ScrolledWindow.new

    text_view = Gtk::TextView.new editable: false, wrap_mode: Gtk::WrapMode.new(2) # WRAP_WORD
    scroll_view.add text_view

    box.pack_start scroll_view, expand: true, fill: true, padding: 10

    @text_buffer = text_view.buffer
    @text_view = text_view
    @scroll_view = scroll_view

    # create a text mark at the end to scroll the view whenever we insert text
    end_iter = Gtk::TextIter.new
    text_buffer.end_iter end_iter
    @end_mark = text_buffer.create_mark "end_mark", end_iter, false

    entry = Gtk::Entry.new
    entry.on_activate do |entry|
      line = entry.text.strip
      entry.text = ""

      if !line.empty?
        append_text("\n>>> #{line}\n\n")
        if handler = @send_message_handler
          handler.call(line)
        end
      end
    end

    box.pack_start entry, expand: false, fill: true, padding: 0

    add box

    entry.grab_focus
  end

  def append_text(text)
    end_iter = Gtk::TextIter.new
    text_buffer.end_iter end_iter
    text_buffer.insert end_iter, text, -1

    GLib.idle_add do
      text_view.scroll_to_mark end_mark, 0.0, true, 0.0, 1.0
      false
    end
  end

  def append_response(response)
    append_text response
  end

  def on_send_message(&block : String ->)
    @send_message_handler = block
  end
end

class Cryum < Gtk::Application
  getter! window : CryumWindow

  def initialize(**kwargs)
    super

    @brium = Brium.new

    on_activate do |application|
      @window = CryumWindow.new(self)
      window.connect "destroy", &->quit
      window.show_all

      window.on_send_message do |message|
        send_message message
      end

      send_message "?"
    end

    # this is to allow Crystal fibers (eg. the spawns for HTTP requests below)
    # to run inside the Gtk main loop
    GLib.timeout_milliseconds(20) do
      Fiber.yield
      true
    end
  end

  def send_message(message)
    spawn do
      window.append_response @brium.send_message(message)
    end
  end
end

app = Cryum.new(application_id: "tech.manas.cryum")
app.run

