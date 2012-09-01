class Firegoby::Uploader
  PRIVACY_PUBLIC            = {:is_public => true,  :is_family => false, :is_friend => false}
  PRIVACY_FRIEND            = {:is_public => false, :is_family => false, :is_friend => true}
  PRIVACY_FAMILY            = {:is_public => false, :is_family => true,  :is_friend => false}
  PRIVACY_FRIEND_AND_FAMLIY = {:is_public => false, :is_family => true,  :is_friend => true}
  PRIVACY_PRIVATE           = {:is_public => false, :is_family => false, :is_friend => false}
  PRIVACY = {
    "PUBLIC"            => PRIVACY_PUBLIC,
    "FRIEND"            => PRIVACY_FRIEND,
    "FAMILY"            => PRIVACY_FAMILY,
    "FRIEND_AND_FAMILY" => PRIVACY_FRIEND_AND_FAMLIY,
    "FAMILY_AND_FRIEND" => PRIVACY_FRIEND_AND_FAMLIY,
    "PRIVATE"           => PRIVACY_PRIVATE,
  }
  WAIT_TICK = 5

  def queue_length
    @queue.length
  end

  def initialize(opts)
    
    @queue           = Queue.new
    @queued_photoset = {}
    @queued_files    = {}
    @privacy         = opts[:privacy]
    @tags            = opts[:tags]
    @remove          = opts[:remove]
    @wait            = opts[:wait]
  end

  def enqueue(dir)
    queued        = 0
    basepath      = File.expand_path(dir)
    photoset_name = photoset_name_from_directory(dir)
    Dir::entries(dir).delete_if {|x| x.start_with?('.') }.each do |f|
      path = "#{basepath}/#{f}"
      next unless File.exist?(path)
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

  def run
    t     = run_queue
    r     = 0
    r_max = @wait / WAIT_TICK

    while true
      Dir::entries(base).delete_if {|x| x.start_with?('.')}.each do |e|
        path = "#{base}/#{e}"
        if File.directory?(path) then
          r = 0 if enqueue(path) > 0 && queue_length > 0
        end
      end
      sleep WAIT_TICK
      if t.status == 'sleep' && queue_length < 1 then
        r += 1
        if r > r_max then
          puts "Stop monitoring. Exit."
          exit
        end
      end
    end
  end

  def run_queue
    Thread.start do
      while task = @queue.pop
        puts task
        case task[:task]
        when :upload_photo
          task_upload_photo task[:opts]
        end
      end
    end
  end

  protected
    def photoset_by_name(name, primary_photo_id_candidate)
      return @queued_photoset[name] if @queued_photoset.key?(name)
      photosets.each do |p|
        return p.id, false if p.title == name
      end
      puts "Create photoset: [#{name} with Photo Id: #{primary_photo_id_candidate}]"
      ps = flickr.photosets.create(name, primary_photo_id_candidate)
      @queued_photoset[name] = ps.id
      return ps.id, true
    end

    def task_upload_photo(opts)
      retries  = 0
      photo_id = nil
      begin
        puts "Upload: #{opts[:file]}"
        photo_id    = flickr.photos.upload.upload_file(opts[:file], nil, nil, @tags, @privacy[:is_public], @privacy[:is_friend], @privacy[:is_family]) if photo_id.nil?
        photoset_id, created = photoset_by_name(opts[:photoset_title], photo_id)
        puts "Insert photo into Photoset [Id: #{photoset_id}, Title: #{opts[:photoset_title]}]: Photo[Id: #{photo_id}, File: #{opts[:file]}]"
        flickr.photosets.addPhoto(photoset_id, photo_id) unless created
        File.unlink(opts[:file]) if @remove
      rescue Exception => e
        retries += 1
        if retries < 10 then
          sleep 3
        elsif retries < 100 then
          sleep 30
        else
          raise "Failed to upload photo"
        end
        puts "#{e}: Retry upload.. #{retries}"
        retry
      end
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
end
