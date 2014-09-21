#!/usr/bin/env ruby

require 'rubygems'
require 'twitter'
require 'daybreak'
require 'dante'

class TweetHandler

  def initialize
    @tweetsaver = TweetSaver.new
  end

  def is_reply(tweet)
    if !tweet.in_reply_to_status_id.to_s.empty?
      true
    else
      false
    end
  end

  def graceful_close
    @tweetsaver.close
  end

  def make_record(tweet)
    text = tweet.text
    id = tweet.id
    screen_name = tweet.user.screen_name
    @tweetsaver.save({:text => text, :screen_name => screen_name, :id => id})
  end

  def handle_tweet(tweet)
    text = tweet.text.dup
    if self.is_reply(tweet)
    else
      self.make_record(tweet)
    end
  end

end

class TweetSaver
  def initialize
    @db = Daybreak::DB.new "tweets.db"
  end

  def save(tweet)
    id = tweet.delete(:id)
    @db.lock do
      @db.set! id, tweet
      @db.flush
      @db.compact
    end
  end

  def close
    @db.lock do
      @db.flush
      @db.compact
      @db.close
    end
  end
end

class Streamer
  def initialize
    @client = Twitter::Streaming::Client.new do |config|
      # dumbomatic (test) credentials
      config.consumer_key       = ENV['consumer_key']
      config.consumer_secret    = ENV['consumer_secret']
      config.access_token        = ENV['access_token']
      config.access_token_secret = ENV['access_token_secret']
    end
    @tweethandler = TweetHandler.new
  end

  def stream
    begin
      @client.user do |object|
        case object
        when Twitter::Tweet
          @tweethandler.handle_tweet(object)
        when Twitter::DirectMessage
        when Twitter::Streaming::StallWarning
          warn "Falling behind!"
        end
      end
    rescue SystemExit, Interrupt
      @tweethandler.graceful_close
      raise
    end
  end
end

streamer = Streamer.new
streamer.stream

