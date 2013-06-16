class Firegoby::Cli::Upload
  def parser
    OptionParser.new do |opts|
      opts.banner = "Usage: #{Firegoby::Cli::SCRIPT_NAME} upload [options]"
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
      opts.on('-p', '--privacy PRIVACY', 'Privacy settings: ' + Firegoby::Uploader::PRIVACY.keys.join(', ')) do |p|
        unless Firegoby::Uploader::PRIVACY.key?(p.upcase)
          puts "Invalid privacy option: #{p}"
          puts opts
          exit
        end
        privacy = Firegoby::Uploader::PRIVACY[p.upcase]
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
  end
end
