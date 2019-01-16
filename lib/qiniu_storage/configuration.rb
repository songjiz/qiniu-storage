require "logger"
require "singleton"

module QiniuStorage
  class Configuration
    include Singleton

    DEFAULT_UPLOAD_RESUMABLE_THRESHOLD = 15 * 1024 * 1024
    DEFAULT_UPLOAD_BLOCK_SIZE = 4 * 1024 * 1024
    DEFAULT_UPLOAD_CHUNK_SIZE = 256 * 1024
    DEFAULT_UPLOAD_TOKEN_EXPIRES_IN = 3600
    DEFAULT_DOWNLOAD_CHUNK_SIZE = 4 * 1024 * 1024
    DEFAULT_DOWNLOAD_TOKEN_EXPIRES_IN = 1 * 24 * 60 * 60

    class << self
      def defaults
        @defaults ||= {
          region: :z0,
          logger: default_logger,
          log_level: :debug,
          debug_mode: false,
          upload_resumable_threshold: DEFAULT_UPLOAD_RESUMABLE_THRESHOLD,
          upload_block_size: DEFAULT_UPLOAD_BLOCK_SIZE,
          upload_chunk_size: DEFAULT_UPLOAD_CHUNK_SIZE,
          upload_token_expires_in: DEFAULT_UPLOAD_TOKEN_EXPIRES_IN,
          upload_max_threads: 2,
          download_chunk_size: DEFAULT_DOWNLOAD_CHUNK_SIZE,
          download_token_expires_in: DEFAULT_DOWNLOAD_TOKEN_EXPIRES_IN,
          use_https: true,
          use_cdn: false,
          skip_crc32_checksum: false,
          enable_upload_cache: true,
          cache_dir: File.join(Dir.home, ".qiniu")
        }
      end

      private
        def default_logger
          Logger.new STDOUT
        end
    end

    attr_accessor :region, :logger, :log_level, :debug_mode, :cache_dir
    attr_accessor :upload_resumable_threshold, :upload_token_expires_in
    attr_accessor :upload_block_size, :upload_chunk_size, :upload_max_threads
    attr_accessor :download_chunk_size, :download_token_expires_in
    attr_accessor :skip_crc32_checksum, :enable_upload_cache, :use_cdn, :use_https

    def initialize
      self.class.defaults.each { |k, v| send("#{k}=", v) }
    end

    def debug_mode?
      debug_mode
    end

    def use_https?
      use_https
    end

    def use_cdn?
      use_cdn
    end

    def skip_crc32_checksum?
      skip_crc32_checksum
    end

    def enable_upload_cache?
      enable_upload_cache
    end
  end
end
