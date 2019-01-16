$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "qiniu_storage"
require "minitest/autorun"
require "securerandom"

QiniuStorage.configure do |config|
  config.use_https = false
  config.use_cdn = false
  config.debug_mode = false
  config.upload_max_threads = 5
end