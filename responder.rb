require 'rubygems'
require 'twitter'
require 'daybreak'
require 'watir-webdriver'

class Tweeter
  def initialize
    @client = Twitter::REST::Client.new do |config|
      config.consumer_key       = ENV['consumer_key']
      config.consumer_secret    = ENV['consumer_secret']
      config.access_token        = ENV['access_token']
      config.access_token_secret = ENV['access_token_secret']
    end
  end

  def tweet query
    text_length = 100 - query[:id].length
    query_text = query[:text][0..text_length]
    text = "@#{query[:screen_name]} #{query_text}"
    @client.update_with_media(text, File.new("tmp/#{query[:id]}.png"), {:in_reply_to_status_id => query[:id]})
  end

  def send_fail query
    puts "failed"
    fail_text = '¯\_[ツ]_/¯ no suggestions for:'
    text_length = 130 - query[:id].length - fail_text.length - query[:screen_name].length
    query_text = "#{fail_text} #{query[:text]}"[0..text_length]
    text = "@#{query[:screen_name]} #{query_text}"
    if @client.update(text, {:in_reply_to_status_id => query[:id]})
      puts "tried to tweet"
    else
      puts "couldn't tweet"
    end
  end
end

class PicMaker
  def initialize
    capabilities = Selenium::WebDriver::Remote::Capabilities.phantomjs("phantomjs.page.settings.userAgent" => "Mozilla/5.0 (Linux; U; Android-4.0.3; en-us; Galaxy Nexus Build/IML74K) AppleWebKit/535.7 (KHTML, like Gecko) CrMo/16.0.912.75 Mobile Safari/535.7")
    driver = Selenium::WebDriver.for :phantomjs, :desired_capabilities => capabilities
    @b = Watir::Browser.new driver
  end

  def remove_divs ids
    script = "var element = document.getElementById(arguments[0]); element.parentNode.removeChild(element);"
    ids.each do |id|
      element = @b.div(id: id)
      if element.exists?
        @b.execute_script script, id
      end
    end
  end

  def close
    @b.close
  end

  def suggestion_count
    count_script = "return document.querySelectorAll('.sbsb_c').length;"
    return @b.execute_script count_script
  end

  def get_image text, id
    @b.goto 'http://google.com'
    self.remove_divs ["mngb", "fbar", "mpd"]

    q = @b.text_field :name => 'q'

    if q.exists?
      q.click
      @b.send_keys text
      sleep 1

      if self.suggestion_count > 0
        if @b.screenshot.save "tmp/#{id}.png"
          return true
        end
      else
        return false
      end

    end
  end
end

class Responder

  def initialize
    @db = Daybreak::DB.new "tweets.db"
    @tweeter = Tweeter.new
    @picmaker = PicMaker.new
  end

  def remove_screen_name text
    name = "@suggestomatic"
    text.slice! "#{name}:"
    text.slice! "#{name} :"
    text.slice! "#{name} "
    text.slice! name
    return text
  end

  def delete id
    @db.lock do
      @db.delete id
      @db.flush
      @db.compact
    end
  end

  def validate query
    valid = true
    if query[:text].empty?
      valid = false
    end

    valid
  end

  def fail query
    self.delete query[:id]
  end

  def check
    queries = self.load
    unless queries.empty?
      queries.each do |query|
        if self.validate(query) == false 
          self.fail query
        else
          image = @picmaker.get_image query[:text], query[:id]
          if image
            if @tweeter.tweet query
              self.delete query[:id]
            end
          else
            @tweeter.send_fail query
            self.delete query[:id]
          end
        end
      end
    end
  end

  def load
    # key = tweet ID
    # text, screen_name
    queries = []
    @db.load
    @db.keys.each do |key|
      id = key
      options = @db[key]
      query = remove_screen_name options[:text]
      screen_name = options[:screen_name]
      queries << {:id => id, :text => query, :screen_name => screen_name}
    end
    queries
  end

  def close_db
    @db.close
  end

end

responder = Responder.new

while true
  responder.check
  sleep 5
end

responder.close_db
