require "test_helper"

class BucketTest < Minitest::Test
  def setup
    @client = QiniuStorage.new(access_key: ENV["QINIU_ACCESS_KEY"], secret_key: ENV["QINIU_SECRET_KEY"])
  end

  def test_name
    name = "mybucket"
    bucket = @client.bucket(name)
    assert_equal bucket.name, name
  end

  def test_acl
    bucket = @client.bucket("test-#{SecureRandom.uuid}")
    bucket.create
    bucket.acl_private
    bucket.acl_public
  ensure
    bucket.drop
  end
  
  def test_create_and_drop
    bucket = @client.bucket("test-#{SecureRandom.uuid}")
    assert_equal bucket.exists?, false
    bucket.create
    sleep 2
    assert_equal bucket.exists?, true
    # Aready exists
    assert_raises QiniuStorage::Error do
      bucket.create :z1
    end
    bucket.drop
    sleep 2
    assert_equal bucket.exists?, false
  end

  def test_rename
    bucket = @client.bucket("test-#{SecureRandom.uuid}")
    bucket.create

    file = bucket.file("hello.txt")
    file.attach StringIO.new("Hello, world")

    bucket.rename file, "hello_world.txt"

    file = bucket.file("hello.txt")
    assert_equal file.exists?, false

    file = bucket.file("hello_world.txt")
    assert_equal file.exists?, true
  ensure
    bucket.drop
  end

  def test_move
    bucket1 = @client.bucket("test-#{SecureRandom.uuid}")
    bucket2 = @client.bucket("test-#{SecureRandom.uuid}")
    bucket1.create
    bucket2.create

    file = bucket1.file("hello.txt")
    file.attach StringIO.new("Hello, world")

    assert_raises ArgumentError do
      bucket1.move file
    end

    bucket1.move(file, to_bucket: bucket2)
    file = bucket1.file("hello.txt")
    assert_equal file.exists?, false
    file = bucket2.file("hello.txt")
    assert_equal file.exists?, true
  ensure
    bucket1.drop
    bucket2.drop
  end

  def test_copy
    bucket1 = @client.bucket("test-#{SecureRandom.uuid}")
    bucket2 = @client.bucket("test-#{SecureRandom.uuid}")
    bucket1.create
    bucket2.create

    file = bucket1.file("hello.txt")
    file.attach StringIO.new("Hello, world")

    assert_raises ArgumentError do
      bucket1.copy file
    end

    bucket1.copy(file, to_key: "hello_world.txt")
    file = bucket1.file("hello_world.txt")
    assert_equal file.exists?, true
    
    bucket1.copy(file, to_bucket: bucket2, to_key: "hello.txt")
    file = bucket2.file("hello.txt")
    assert_equal file.exists?, true
  ensure
    bucket1.drop
    bucket2.drop
  end

  def test_fetch
    bucket = @client.bucket("test-#{SecureRandom.uuid}")
    bucket.create
    file = bucket.fetch("http://devtools.qiniu.com/qiniu.png", "qiniu.png")
    assert_equal file.key, "qiniu.png"
    assert_equal file.etag.nil?, false
    assert file.mime_type, "image/png"
    assert_equal file.image?, true

    job = bucket.async_fetch("http://devtools.qiniu.com/qiniu.png")
    assert_kind_of QiniuStorage::AsyncFetchJob, job
    assert_equal true, !job.job_id.nil?
    assert_equal true, !job.wait.nil?
    assert_equal true, job.respond_to?(:refresh)
    result = job.refresh
    assert_equal true, result.key?("id")
    assert_equal true, result.key?("wait")
  ensure
    bucket.drop
  end

  def test_batch
    bucket = @client.bucket("test-#{SecureRandom.uuid}")
    bucket.create

    files = bucket.files
    assert_kind_of QiniuStorage::Object::Bundle, files
    assert_equal files.empty?, true

    file = bucket.file("hello.txt")
    tmpio = StringIO.new("Hello, world")
    file.attach tmpio
    assert_kind_of Hash, file.stat
    file.chmime "text/plain"
    assert_equal "text/plain", file.mime_type
    assert_equal tmpio.size, file.size

    files.reload
    assert_equal files.empty?, false

    5.times do |i|
      file = bucket.file("hello-#{i}.txt")
      tmpio = StringIO.new("Hello, world")
      file.attach(tmpio)
      tmpio = nil
    end

    5.times do |i|
      file = bucket.file("order-#{i}")
      tmpio = StringIO.new("order #{i}")
      file.attach(tmpio)
      tmpio = nil
    end

    files = bucket.files(limit: 2)
    assert_equal files.next?, false
    
    files = bucket.files(prefix: "order")
    files.each do |file|
      assert_match /^order/, file.key
    end

    files.low_freq
    files.each { |f| assert_equal f.low_freq?, true }
    files.standardize
    files.each { |f| assert_equal f.standard?, true }
    files.disable
    files.each { |f| assert_equal f.disabled?, true }
    files.enable
    files.each { |f| assert_equal f.enabled?, true }
    files.chmime "text/plain"
    files.each { |f| assert_equal f.mime_type, "text/plain" }
    files.stat
    files.each { |f| assert !f.etag.nil? }
  ensure
    bucket.drop
  end

  # def test_append
  #   bucket = @client.bucket("test-#{SecureRandom.uuid}")
  #   bucket.create

  #   QiniuStorage.configuration.http_debug_mode = true
  #   obj = bucket.object("hello.txt")
  #   part1 = StringIO.new("Hello")
  #   part2 = StringIO.new(", World!")
  #   obj.attach part1
  #   bucket.append obj.key, part2
  #   obj.stat
  #   assert_equal part1.size + part2.size, obj.size
  # ensure
  #   bucket.drop
  # end
end
