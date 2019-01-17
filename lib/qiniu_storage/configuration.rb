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
          zone: ENV.fetch("QINIU_ZONE", :z0),
          logger: default_logger,
          log_level: ENV.fetch("QINIU_LOG_LEVEL", :debug),
          http_debug_mode: ENV.fetch("QINIU_HTTP_DEBUG_MODE", false),
          upload_resumable_threshold: ENV.fetch("QINIU_UPLOAD_RESUMABLE_THRESHOLD", DEFAULT_UPLOAD_RESUMABLE_THRESHOLD),
          upload_block_size: ENV.fetch("QINIU_UPLOAD_BLOCK_SIZE", DEFAULT_UPLOAD_BLOCK_SIZE),
          upload_chunk_size: ENV.fetch("QINIU_UPLOAD_CHUNK_SIZE", DEFAULT_UPLOAD_CHUNK_SIZE),
          upload_token_expires_in: ENV.fetch("QINIU_UPLOAD_TOKEN_EXPIRES_IN", DEFAULT_UPLOAD_TOKEN_EXPIRES_IN),
          upload_max_threads: ENV.fetch("QINIU_UPLOAD_MAX_THREADS", 2),
          download_chunk_size: ENV.fetch("QINIU_DOWNLOAD_CHUNK_SIZE", DEFAULT_DOWNLOAD_CHUNK_SIZE),
          download_token_expires_in: ENV.fetch("QINIU_DOWNLOAD_TOKEN_EXPIRES_IN", DEFAULT_DOWNLOAD_TOKEN_EXPIRES_IN),
          use_https: ENV.fetch("QINIU_USE_HTTPS", true),
          use_cdn: ENV.fetch("QINIU_USE_CDN", true),
          skip_crc32_checksum: ENV.fetch("QINIU_SKIP_CRC32_CHECKSUM", false),
          use_upload_cache: ENV.fetch("QINIU_USE_UPLOAD_CACHE", true),
          cache_dir: ENV.fetch("QINIU_CACHE_DIR", File.join(Dir.home, ".qiniu"))
        }
      end

      private
        def default_logger
          Logger.new STDOUT
        end
    end

    attr_accessor :zone, :logger, :log_level, :http_debug_mode, :cache_dir
    attr_accessor :upload_resumable_threshold, :upload_token_expires_in
    attr_accessor :upload_block_size, :upload_chunk_size, :upload_max_threads
    attr_accessor :download_chunk_size, :download_token_expires_in
    attr_accessor :skip_crc32_checksum, :use_upload_cache, :use_cdn, :use_https

    def initialize
      self.class.defaults.each { |k, v| send("#{k}=", v) }
    end

    def http_debug_mode?
      http_debug_mode
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

    def use_upload_cache?
      use_upload_cache
    end
  end
end
