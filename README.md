# QiniuStorage

[![Build Status](https://travis-ci.com/songjiz/qiniu-storage.svg?branch=master)](https://travis-ci.com/songjiz/qiniu-storage)

非官方七牛云存储 Gem , 但更好用!

## 安装

在您的 Ruby 应用程序的 Gemfile 文件中，添加如下一行代码：

```ruby
gem "qiniu-storage"
```

然后在应用程序所在的目录下，运行 bundle 安装依赖包：

```bash
$ bundle
```

或者使用 Ruby 的包管理器 gem 进行安装：

```bash
$ gem install qiniu-storage
```

## 使用

 ### 配置

 ```ruby
  QiniuStorage.configure do |config|
    config.zone = :z0
    config.logger = Logger.new(STDOUT)
    config.log_level = :debug
    config.http_debug_mode = false
    config.upload_resumable_threshold = 15 * 1024 * 1024
    config.upload_block_size = 4 * 1024 * 1024
    config.upload_chunk_size = 256 * 1024
    config.upload_token_expires_in = 3600
    config.upload_max_threads = 2
    config.download_chunk_size = 4 * 1024 * 1024
    config.download_token_expires_in = 1 * 24 * 60 * 60
    config.use_ssl = true
    config.use_cdn = false
    config.skip_crc32_checksum = false
    config.use_upload_cache = true
    config.cache_dir = File.join(Dir.home, ".qiniu")
  end

  client = QiniuStorage.new(access_key: "your_access_key", secret_key: "your_secret_key")

  client = QiniuStorage.new # 使用 ENV['QINIU_ACCESS_KEY'] 和 ['QINIU_SECRET_KEY']
 ```

  默认会读取以下 `ENV` 变量:
  - QINIU_ACCESS_KEY
  - QINIU_SECRET_KEY
  - QINIU_ZONE
  - QINIU_HTTP_DEBUG_MODE
  - QINIU_UPLOAD_RESUMABLE_THRESHOLD
  - QINIU_UPLOAD_BLOCK_SIZE
  - QINIU_UPLOAD_CHUNK_SIZE
  - QINIU_UPLOAD_TOKEN_EXPIRES_IN
  - QINIU_UPLOAD_MAX_THREADS
  - QINIU_DOWNLOAD_CHUNK_SIZE
  - QINIU_DOWNLOAD_TOKEN_EXPIRES_IN
  - QINIU_USE_SSL
  - QINIU_USE_CDN
  - QINIU_SKIP_CRC32_CHECKSUM
  - QINIU_USE_UPLOAD_CACHE
  - QINIU_CACHE_DIR

 ### Bucket 接口

 ```ruby
  # 获取列表
  buckets = client.buckets
  # => [#<QiniuStorage::Bucket:0x00007fdf2aa3f280 @name="test-1547198528", @client=#<QiniuStorage::Client:0x00007fdf2c837260 @access_key="", @secret_key="">, @region=:z0>, ...]

  # 创建
  bucket = client.bucket('test')
  # => #<QiniuStorage::Bucket:0x00007fdf2b298648 @name="test", @client=#<QiniuStorage::Client:0x00007fdf2c837260 @access_key="", @secret_key="">, @region=:z0>

  bucket.create
  # 指定存储区域
  bucket.create(:z1)
  bucket.exists?
  # => true

  # 获取空间域名
  bucket.domains
  # =>  ["xxx.bkt.clouddn.com"]

  # 设置访问权限
  bucket.acl_private
  bucket.acl_public

  # 删除
  bucket.drop

  bucket.exists?
  # => false

  # 获取文件列表
  objs = bucket.objects
  objs = bucket.objects limit: 1000, prefix: nil, delimiter: nil, marker: nil

  # 获取文件
  obj = bucket.object("hello.txt")

  # 查看文件元信息
  bucket.stat "hello.txt"
  bucket.metadata "hello.txt"

  # 删除文件
  bucket.remove "hello.txt"
  bucket.delete "hello.txt"

  # 重命名文件
  bucket.rename "hello.txt", "hello"
  bucket.rename "hello.txt", "hello", force: true

  # 复制文件
  bucket.copy "hello", to_key: "hello1"
  bucket.copy "hello", to_bucket: "test-2"
  bucket2 = client.bucket("test-2")
  bucket.copy "hello", to_bucket: bucket2
  bucket.copy "hello", to_bucket: bucket2, to_key: "hello_world", force: true

  # 移动文件
  bucket.move "hello", to_key: "hello1"
  bucket.move "hello", to_bucket: "test-2"
  bucket2 = client.bucket("test-2")
  bucket.move "hello", to_bucket: bucket2
  bucket.move "hello", to_bucket: bucket2, to_key: "hello_world", force: true

  # 设置文件有效周期
  bucket.life_cycle "hello", 2
  bucket.delete_after_days "hello", 2

  # 修改文件状态
  bucket.enable "hello"
  bucket.disable "hello"
  bucket.chstatus "hello", 1
  bucket.chstatus "hello", 0

  # 修改文件类型
  bucket.standardize "hello"
  bucket.low_freq "hello"
  bucket.chtype "hello", 0
  bucket.chtype "hello", 1

  # 修改元数据
  bucket.chmime "hello", "text/plain"

  # 从url抓取资源
  bucket.fetch "http://devtools.qiniu.com/qiniu.png"
  # => #<QiniuStorage::Object:0x00007fe049b03d68 @_metadata={:fsize=>163469, :hash=>"FpHyF0kkil3sp-SaXXX8TBJY3jDh", :key=>"FpHyF0kkil3sp-SaXXX8TBJY3jDh", :mime_type=>"image/png"}>
  bucket.fetch "http://devtools.qiniu.com/qiniu.png", "qiniu.png"
  # => #<QiniuStorage::Object:0x00007fe0491f0488 @_metadata={:fsize=>163469, :hash=>"FpHyF0kkil3sp-SaXXX8TBJY3jDh", :key=>"qiniu.png", :mime_type=>"image/png"}>

  # 从url抓取资源(异步)
  job = bucket.async_fetch "http://devtools.qiniu.com/qiniu.png"
  # => #<QiniuStorage::AsyncFetchJob:0x00007ff0f623d108 ...>
  job.refresh

  # 下载文件
  body = bucket.download("hello")
  partial = bucket.download("hello", range: 0..1024)
  partial = bucket.download("hello", range: [0, 1024])
  partial = bucket.download("hello", range: "bytes=0-1024")
  bucket.streaming_download("hello") do |bytes|
    # ...
  end
  bucket.streaming_download("hello", offset: 0, chunck_size: 1024) do |bytes|
    # ...
  end
 ```

### Object 接口

```ruby
# 资源列举
objs = bucket.objects
# => #<QiniuStorage::Object::Bundle:0x00007fa233319ef8 ...>
objs.keys
# => ['key1', 'key2']
objs.names
# => ['test:key1', 'test:key2']

# 分页
objs.next?
# => true
next_objs = objs.next
# => #<QiniuStorage::Object::Bundle:0x00007fa2339b5a78 ...>
objs.next?
# => false

# 批量操作
objs.stat
# => [{"code"=>200, "data"=>{"fsize"=>4, "hash"=>"FhBzq2zaS5kc0p-eg6MH80AErpMn", ...}}, ... ]
objs.delete_all 
# => [{"code"=>200}, {"code"=>200}]
objs.move "other-bucket"
objs.move "other-bucket", force: true
objs.copy "other-bucket" 
objs.copy "other-bucket", force: true

# 单文件
obj = bucket.object("xxxx")
# => #<QiniuStorage::Object:0x00007fdf2c879980 @bucket=#<QiniuStorage::Bucket:0x00007fdf2aaf4bf8 @name="test", @client=...>

# 文件元信息
obj.stat
# 或者
obj.metadata
# => {"fsize"=>12, "hash"=>"FrfiPsKa8isLTkHaMeho1XImEhyE", "md5"=>"5NfxtO0uQtFYmPSyewGdpA==", "mimeType"=>"text/plain", "putTime"=>15475498406276861, "type"=>0}
obj.fsize # => 12
obj.size # => 12
obj[:fsize] # => 12
obj.etag # => "FrfiPsKa8isLTkHaMeho1XImEhyE"
obj[:hash] # => "FrfiPsKa8isLTkHaMeho1XImEhyE"
obj.md5 # => "5NfxtO0uQtFYmPSyewGdpA=="
obj[:md5] # => "5NfxtO0uQtFYmPSyewGdpA=="
obj.mime_type # => "text/plain"
obj[:mime_type] # => "text/plain"
obj.text? # => true
obj.image? # => false
obj.video? # => false
obj.audio? # => false
obj.enabled? # => true
obj.disabled? # => false
# ...

# 修改文件状态
obj.enable
obj.enabled? # => true
obj.disable
obj.disabled? # => true

# 设置文件生命周期
obj.life_cycle 1
# 或者
obj.delete_after_days 1

# 修改文件存储类型
obj.standardize
obj.standard? # => true
obj.low_freq
obj.low_freq? # => true

# 修改元信息
obj.chmime("image/png")
obj.image? # => true

# 移动/重命名
obj.rename "hello"
obj.rename "hello", force: true

obj.move(to_bucket: "test-2")
obj.move(to_bucket: "test-2", force: true)
obj.move(to_bucket: "test-2", to_key: "hello.txt")

# 复制
obj.copy to_bucket: "test-2"
obj.copy to_bucket: "test-2", to_key: "balabala"

# 删除
obj.remove
# 或者
obj.delete

# 从url抓取资源
obj = bucket.object("qiniu.png")
obj.fetch "http://devtools.qiniu.com/qiniu.png"
obj.image?
# => true
obj.img_info
# => {"size":163469,"format":"png","width":900,"height":900,"colorModel":"rgba"}

# 从url抓取资源(异步)
obj = bucket.object("qiniu.png")
obj.async_fetch "http://devtools.qiniu.com/qiniu.png"
# => #<QiniuStorage::AsyncFetchJob:0x00007ff0f623d108 ...>
obj.async_fetch_job
# => #<QiniuStorage::AsyncFetchJob:0x00007ff0f623d108 ...>
obj.async_fetch_job.refresh


# 上传
obj.attach(StringIO.new("Hello, world")) # 根据 QiniuStorage.configuration.upload_resumable_threshold 值自动选择上传方式
# 或者
obj.put(StringIO.new("Hello, world"))
# 直传文件(小文件)
obj.multipart_upload StringIO.new("Hello, world")
# 可恢复上传(大文件)
obj.resumable_upload StringIO.new("Hello" * 1024 * 1024)

# 下载文件
body = obj.download
partial = obj.download range: 0..1024
partial = obj.download range: [0, 1024]
partial = obj.download range: "bytes=0-1024"
obj.streaming_download do |bytes|
  # ...
end

obj.streaming_download(offset: 1000, chunk_size: 1024) do |bytes|
  # ...
end
```
