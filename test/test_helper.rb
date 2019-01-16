$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "qiniu_storage"
require "minitest/autorun"
require "securerandom"

QiniuStorage.configure do |config|
  config.use_https = ENV.fetch("QINIU_USE_HTTPS", false)
  config.use_cdn = ENV.fetch("QINIU_USE_CDN", false)
  config.debug_mode = ENV.fetch("QINIU_DEBUG_MODE", false)
  config.upload_max_threads = 5
end