require "test_helper"

class ObjectTest < Minitest::Test
	def setup
    @client = QiniuStorage.new(access_key: ENV["QINIU_ACCESS_KEY"], secret_key: ENV["QINIU_SECRET_KEY"])
  end
  
  def test_create_and_remove
    bucket = @client.bucket("test-#{SecureRandom.uuid}")
    bucket.create

    obj = bucket.object("hello.txt")
    assert_equal "hello.txt", obj.key
    assert_equal bucket, obj.bucket
    assert_equal false, obj.exists?
    tiny_file = StringIO.new("Hello, world")
    obj.attach tiny_file
    assert_equal true, obj.exists?
    obj.stat
    assert_equal tiny_file.size, obj.size

    big_file = StringIO.new("Hello" * 5 * 1024 * 1024)
    obj.attach big_file
    obj.stat
    assert_equal big_file.size, obj.size

    tiny_file = StringIO.new("Hello, world")
    obj.multipart_upload tiny_file
    obj.stat
    assert_equal tiny_file.size, obj.size

    big_file = StringIO.new("Hello" * 1024 * 1024)
    obj.resumable_upload(big_file)
    obj.stat
    assert_equal big_file.size, obj.size

    obj.remove
    assert_equal false, obj.exists?
    assert_raises QiniuStorage::Error do
      obj.remove
    end
  ensure
    bucket.drop
  end

  def test_stat
    bucket = @client.bucket("test-#{SecureRandom.uuid}")
    bucket.create

    obj = bucket.object("hello.txt")
    data = StringIO.new("Hello, world")
    obj.attach data
    obj.stat

    assert_equal data.size, obj.size
    assert_equal QiniuStorage.qetag(data), obj.etag
    assert_equal obj[:hash], obj.etag
    assert_equal false, obj.md5.nil?
    assert_equal obj[:md5], obj.md5
    assert_equal true, obj.standard?

    obj.low_freq
    obj.stat
    assert_equal true, obj.low_freq?
    assert_equal false, obj.standard?

    obj.standardize
    assert_equal false, obj.low_freq?
    assert_equal true, obj.standard?
    obj.stat
    assert_equal false, obj.low_freq?
    assert_equal true, obj.standard?

    obj.chmime "text/plain"
    assert_equal "text/plain", obj.mime_type
    assert_equal obj[:mime_type], obj.mime_type
    assert_equal true, obj.text?
    obj.stat
    assert_equal "text/plain", obj.mime_type
    assert_equal obj[:mime_type], obj.mime_type
    assert_equal true, obj.text?

    assert_equal true, obj.enabled?
    obj.disable
    assert_equal true, obj.disabled?
    obj.stat
    assert_equal true, obj.disabled?
  ensure
    bucket.drop
  end

  def test_life_cycle
    bucket = @client.bucket("test-#{SecureRandom.uuid}")
    bucket.create

    obj = bucket.object("hello.txt")
    data = StringIO.new("Hello, world")
    obj.attach data
    obj.life_cycle 1
  ensure
    bucket.drop
  end

  def test_move_and_rename_and_copy
    bucket1 = @client.bucket("test-#{SecureRandom.uuid}")
    bucket2 = @client.bucket("test-#{SecureRandom.uuid}")
    bucket1.create
    bucket2.create

    obj = bucket1.object("hello.txt")
    data = StringIO.new("Hello, world")
    obj.attach data
    obj.rename "hello_world.txt"
    assert_equal "hello_world.txt", obj.key
    assert_equal true, bucket1.object("hello_world.txt").exists?
    assert_equal false, bucket1.object("hello.txt").exists?
    assert_equal true, obj.exists?

    assert_raises ArgumentError do
      obj.move
    end
    # QiniuStorage::Error: file exists
    assert_raises QiniuStorage::Error do
      obj.move to_key: "hello_world.txt"
    end

    obj.move to_key: "hello_world.txt", force: true

    # QiniuStorage::Error: file exists
    assert_raises QiniuStorage::Error do
      obj.rename "hello_world.txt"
    end
    obj.rename "hello_world.txt", force: true

    obj.move(to_bucket: bucket2)
    assert_equal false, bucket1.object("hello_world.txt").exists?
    assert_equal true, obj.exists?
    assert_equal bucket2, obj.bucket

    assert_raises ArgumentError do
      obj.copy
    end
    # QiniuStorage::Error: file exists
    assert_raises QiniuStorage::Error do
      obj.copy to_key: "hello_world.txt"
    end
    obj.copy to_key: "hello_world.txt", force: true
    assert_equal 1, bucket2.objects(prefix: "hello_world").size
    copied_obj = obj.copy to_key: "hello_world(Copy).txt"
    assert_equal true, copied_obj.exists?
    assert_equal copied_obj.bucket, obj.bucket
    assert_equal "hello_world(Copy).txt", copied_obj.key
    obj.stat
    copied_obj.stat
    assert_equal obj.size, copied_obj.size
    assert_equal obj.etag, copied_obj.etag

    copied_obj = obj.copy to_bucket: bucket1
    assert_equal bucket1, copied_obj.bucket
    assert_equal true, copied_obj.exists?
  ensure
    bucket1.drop
    bucket2.drop
  end

  def test_fetch
    bucket = @client.bucket("test-#{SecureRandom.uuid}")
    bucket.create

    obj = bucket.object("qiniu.png")
    obj.fetch "http://devtools.qiniu.com/qiniu.png"
    assert_equal true, obj.exists?
    assert_equal true, obj.image?
  ensure
    bucket.drop
  end

  def test_batch
    bucket1 = @client.bucket("test-#{SecureRandom.uuid}")
    bucket2 = @client.bucket("test-#{SecureRandom.uuid}")
    bucket1.create
    bucket2.create

    data = StringIO.new("Hello, world")
    5.times do |i|
      data.rewind
      file = bucket1.object("hello-#{i}")
      file.attach(data)
    end

    objs = bucket1.objects(prefix: "hello", limit: 2)
    objs.metadata
    objs.each do |obj|
      assert_equal data.size, obj.size
      assert_equal QiniuStorage.qetag(data), obj.etag
    end

    objs.chmime "text/plain"
    objs.each do |obj|
      assert_equal "text/plain", obj.mime_type
      obj.metadata
      assert_equal "text/plain", obj.mime_type
    end

    objs.enable
    objs.each do |obj|
      assert_equal true, obj.enabled?
    end

    objs.disable
    objs.each do |obj|
      assert_equal true, obj.disabled?
    end

    objs.standardize
    objs.each do |obj|
      assert_equal true, obj.standard?
    end

    objs.low_freq
    objs.each do |obj|
      assert_equal true, obj.low_freq?
    end

    objs.move(bucket2)
    objs.each do |obj|
      assert_equal true, obj.exists?
      assert_equal true, obj.bucket.name == bucket2.name
    end

    assert_equal true, objs.next?
    objs = objs.next
    objs.copy(bucket2)
    objs.each do |obj|
      assert_equal true, bucket2.object(obj.key).exists?
    end
    objs.delete_all
    objs.each do |obj|
      assert_equal false, obj.exists?
    end
    
    objs = objs.next
    assert_equal false, objs.next?    
  ensure
    bucket1.drop
    bucket2.drop
  end
end