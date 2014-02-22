#!/usr/bin/env ruby

$LOAD_PATH.push('.')

require 'flickr'
require 'yaml'
require 'thread'
require 'mini_exiftool'
require 'optparse'
require 'launchy'

class Firegoby
  PRIVACY_PUBLIC            = {:is_public => true,  :is_family => false, :is_friend => false}
  PRIVACY_FRIEND            = {:is_public => false, :is_family => false, :is_friend => true}
  PRIVACY_FAMILY            = {:is_public => false, :is_family => true,  :is_friend => false}
  PRIVACY_FRIEND_AND_FAMILY = {:is_public => false, :is_family => true,  :is_friend => true}
  PRIVACY_PRIVATE           = {:is_public => false, :is_family => false, :is_friend => false}
  PRIVACY = {
    'PUBLIC' => PRIVACY_PUBLIC,
    'FRIEND' => PRIVACY_FRIEND,
    'FAMILY' => PRIVACY_FAMILY,
    'FRIEND_AND_FAMILY' => PRIVACY_FRIEND_AND_FAMILY,
    'FAMILY_AND_FRIEND' => PRIVACY_FRIEND_AND_FAMILY,
    'PRIVATE' => PRIVACY_PRIVATE,
  }
  WAIT_TICK = 5

  def self.run(args)
    base    = nil
    tags    = nil
    wait    = 60
    privacy = PRIVACY_PRIVATE
    remove  = false

    opts = OptionParser.new do |opts|
      opts.banner = 'Usage: firegoby.rb [options]'
      opts.separator ''
      opts.separator 'Required options:'

      opts.on('-b', '--base BASE_DIR', 'Base directory') do |b|
        base = b
      end

      opts.separator ''
      opts.separator 'Specific options:'
      opts.on('-r', '--remove', 'Remove after upload') do |r|
        remove = r
      end
      opts.on('-p', '--privacy PRIVACY', 'Privacy settings: ' + PRIVACY.keys.join(", ")) do |p|
        unless PRIVACY.key?(p.upcase)
          puts "Invalid privacy option: #{p}"
          puts opts
          exit
        end
        privacy = PRIVACY[p.upcase]
      end
      opts.on('-t', '--tags TAGS', 'Tags') do |t|
        tags = t
      end
      opts.on('-w', '--wait SECONDS', 'Maximum wait for shutdown') do |w|
        wait = w.to_i
      end
      opts.separator ''
      opts.separator 'Common options:'
      opts.on_tail('-h', '--help', 'Show this message') do
        puts opts
        exit
      end
    end
    opts.parse!(args)
    if base.nil?
      puts opts
      exit
    end

    fo    = Firegoby.new({
      :privacy => privacy,
      :tags    => tags,
      :remove  => remove,
      })
    t     = fo.run_queue
    r     = 0
    r_max = wait / WAIT_TICK

    while true
      if fo.queue_length < 1
        Dir::entries(base).delete_if {|x| x.start_with?('.')}.each do |e|
          path = "#{base}/#{e}"
          if File.directory?(path) then
            r = 0 if fo.enqueue(path) > 0
          end
        end
        r = 0 if fo.enqueue_basedir(base) > 0
      end

      sleep WAIT_TICK
      if t.status == 'sleep' && fo.queue_length < 1
        r += 1
        if r > r_max
          puts 'Stop monitoring. Exit.'
          exit
        end
      end
    end
  end

  def queue_length
    @queue.length
  end

  def initialize(opts)
    @queue           = Queue.new
    @queued_photoset = {}
    @queued_files    = {}
    @upload_count    = 0
    @privacy         = opts[:privacy]
    @tags            = opts[:tags]
    @remove          = opts[:remove]
  end

  def define_photoset(path)
    begin
      exif = MiniExiftool.new path

      if exif.create_date.nil? || exif.create_date == '--'
        File.ctime(path).strftime('%Y-%m')
      else
        exif.create_date.strftime('%Y-%m')
      end
    rescue
      begin
        File.ctime(path).strftime('%Y-%m')
      rescue
        nil
      end
    end
  end

  def enqueue_basedir(dir)
    queued        = 0
    Dir::entries(dir).
        delete_if {|x| x.start_with?('.') }.
        keep_if {|x| x.downcase.end_with?('.jpg') || x.downcase.end_with?('.jpeg') }.
        sort.
        each do |f|
      path = "#{dir}/#{f}"
      photoset = define_photoset(path)

      unless photoset.nil?
        enqueue_task(:upload_photo, {
            :photoset_title => photoset,
            :file => path,
        })
        @queued_files[path] = true
        queued += 1
      end
    end
    queued
  end

  def enqueue(dir)
    queued        = 0
    basepath      = File.expand_path(dir)
    photoset_name = photoset_name_from_directory(dir)
    Dir::entries(dir).delete_if {|x| x.start_with?('.') }.each do |f|
      path = "#{basepath}/#{f}"
      next unless File.size?(path)
      next if @queued_files.key?(path)
      enqueue_task(:upload_photo, {
        :photoset_title => photoset_name,
        :file           => path,
        })
      @queued_files[path] = true
      queued += 1
    end

    queued
  end

  def run_queue
    Thread.start do
      while (task = @queue.pop)
        puts task
        case task[:task]
        when :upload_photo
          task_upload_photo task[:opts]
        else
          # nop
        end
      end
    end
  end

  protected
    def photoset_by_name(name, primary_photo_id)
      return @queued_photoset[name] if @queued_photoset.key?(name)
      photosets.each do |p|
        return p.id, false if p.title == name
      end
      puts "Create photoset: [#{name} with Photo Id: #{primary_photo_id}]"
      ps = flickr.photosets.create(name, primary_photo_id)
      @queued_photoset[name] = ps.id
      return ps.id, true
    end

    def task_upload_photo(opts)
      retries  = 0
      photo_id = nil
      return unless File.size?(opts[:file])
      begin
        puts "Uploading[#{@upload_count}]: #{opts[:file]}"
        photo_id    = flickr.photos.upload.upload_file(opts[:file], nil, nil, @tags, @privacy[:is_public], @privacy[:is_friend], @privacy[:is_family]) if photo_id.nil?
        photoset_id, created = photoset_by_name(opts[:photoset_title], photo_id)
        puts "Insert photo into Photoset [Id: #{photoset_id}, Title: #{opts[:photoset_title]}]: Photo[Id: #{photo_id}, File: #{opts[:file]}]"
        flickr.photosets.addPhoto(photoset_id, photo_id) unless created
        File.unlink(opts[:file]) if @remove
      rescue Exception => e
        retries += 1
        if retries < 10 then
          sleep 3
        else
          puts "Givin up on upload due to #{e}: #{opts[:file]} skipped."
          return
        end
        puts "#{e} #{e.backtrace.join(', ')}: Retry upload.. #{retries}"
        retry
      end
      @upload_count += 1
      photo_id
    end

    def photoset_name_from_directory(dir)
      path = File.expand_path(dir)
      if File.directory?(path) then
        d = path
      else
        d = File.dirname(path)
      end
      File.basename(d)
    end

    def enqueue_task(task, opts = {})
      @queue.push({
        :task => task,
        :opts => opts,
        })
    end

    def photoset_exists(name)
      return true unless @queued_photoset.key?(name)
      photosets.each do |p|
        return true if p.title == name
      end
      false
    end

    def photosets
      if @photosets.nil? then
        @photosets = flickr.photosets.getList
      end
      @photosets
    end

  def api_key
    'c9ff9c9a49ec22663219d4848aa3e4a3'
  end

  def api_secret
    '2d87172f8a72d07c'
  end

  def flickr
    if @flickr.nil?
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

Firegoby.run(ARGV)
