require "forwardable"
require "qiniu_storage/version"
require "qiniu_storage/configuration"
require "qiniu_storage/helper"
require "qiniu_storage/error"
require "qiniu_storage/zone"
require "qiniu_storage/operation"
require "qiniu_storage/bucket"
require "qiniu_storage/object"
require "qiniu_storage/uploader"
require "qiniu_storage/client"

module QiniuStorage
  class << self
    include QiniuStorage::Helper
    extend Forwardable
    
    def_delegators :configuration, :logger, :log_level, :cache_dir
    def_delegators :configuration, :use_https?, :use_cdn?, :skip_crc32_checksum?, :enable_upload_cache?

    def new(options)
      Client.new options
    end

    def configuration
      Configuration.instance
    end

    def configure(&block)
      if block.arity < 1
        configuration.instance_eval(&block)
      else
        yield configuration
      end
    end
  end
end
