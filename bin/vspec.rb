#!/usr/bin/env ruby
# encoding: utf-8

require 'tempfile'

class Vspec

  private

  module Helper extend self

    def which cmd
      dir = ENV['PATH'].split(':').find {|p| File.executable? File.join(p, cmd)}
      File.join(dir, cmd) unless dir.nil?
    end

    def locate query
      case RbConfig::CONFIG['host_os']
      when /^darwin/
        `mdfind #{query}`
      when /^linux/
        `locate #{query}`
      else
        raise "unknown environment"
      end
    end
  end

  def detect_from_rtp
    @@detect_from_rtp_cache ||= `vim -u ~/.vimrc -e -s -c 'set rtp' -c q`
                          .match(/^\s+runtimepath=(.+)\n$/)[0]
                          .split(',')
                          .find{|p| p =~ /vim-vspec$/ }
  end

  def detect_from_locate
    @@detect_from_locate_cache ||= Helper::locate('vim-vspec').split("\n").first
  end

  def has_vspec? dir
    File.executable?(File.expand_path(File.join dir, 'bin', 'vspec'))
  end

  def detect_vspec_root
    case
    when has_vspec?(detect_from_rtp)
      detect_from_rtp
    when has_vspec?(detect_from_locate)
      detect_from_locate
    when Helper::which('vspec')
      File.dirname(File.dirname(Helper::which('vspec')))
    when has_vspec?("#{ENV['HOME']}/.vim")
      "#{ENV['HOME']}/.vim"
    when has_vspec?("vim-vspec")
      "./vim-vspec"
    else
      raise "vspec is not found"
    end
  end

  def driver_script filename,autoloads
    Tempfile.open(File.basename filename) do |f|
      f.print <<-SCRIPT
        function s:main()
          let standard_paths = split(&runtimepath, ',')[1:-2]
          let non_standard_paths = #{autoloads.push(@vspec_root).reverse.inspect}
          let all_paths = copy(standard_paths)
          for i in non_standard_paths
            let all_paths = [i] + all_paths + [i . '/after']
          endfor
          let &runtimepath = join(all_paths, ',')

          1 verbose call vspec#test('#{filename}')
          qall!
        endfunction
        call s:main()
      SCRIPT
      f.path
    end
  end

  public

  def initialize( path: File.executable?("/usr/local/bin/vim") ? "/usr/local/bin" : "",
                  vspec_root: detect_vspec_root )
    @path = path
    @vspec_root = vspec_root
    @vspec = File.join vspec_root, "bin", "vspec"
  end

  def run(file, autoloads: [])
    driver = driver_script file, autoloads
    cmd = [
      "PATH=#{@path}:$PATH",
      "vim",
      "NONE -i NONE -N -e -s",
      "-S #{driver}",
      "2>&1",
    ].join(' ')
    @result = `#{cmd}`.gsub(/\r$/, '')
    File.delete driver
    @success = @result.scan(/^Error detected while processing function/).empty?
  end

  def count_failed
    @result.scan(/^not ok /).size if @success && @result
  end

  def all_passed?
    count_failed == 0 if @success && @result
  end

  def success?
    @success
  end

  attr_reader :result

end

#
# main
#
if __FILE__ == $PROGRAM_NAME

  def help
    "Usage: #{__FILE__} [{non-standard-runtimepath} ...] {input-script}"
  end

  if ARGV.size == 0 || ARGV.include?('-h') || ARGV.include?('--help')
    STDERR.puts help
    exit 0
  end

  test_script = ARGV.pop

  v = Vspec.new
  v.run test_script, autoloads: ARGV
  puts v.result.gsub(/^\n/, '')
  exit 1 unless v.success? && v.all_passed?

end # if __FILE__ = $PROGRAM_NAME
