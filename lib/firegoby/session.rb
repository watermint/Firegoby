require "flickr"
require "launchy"

class Firegoby::Session
  def api_key
    'c9ff9c9a49ec22663219d4848aa3e4a3'
  end

  def api_secret
    '2d87172f8a72d07c'
  end

  def flickr
    if @flickr.nil? then
      @flickr = Flickr.new(token_file, api_key, api_secret)
      auth_token
    end
    @flickr
  end

  def token_file
    "#{ENV['HOME']}/.flickr_firegoby"
  end

  def auth_token
    unless @flickr.auth.token
      Launchy.open(@flickr.auth.login_link)
      STDIN.gets
      @flickr.auth.getToken
      @flickr.auth.cache_token
    end
  end

  def method_missing(method, *args)
    flickr.send(method, *args)
  end
end
