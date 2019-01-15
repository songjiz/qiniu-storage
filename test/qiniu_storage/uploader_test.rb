require "test_helper"

class UploaderTest < Minitest::Test
	def setup
    @client = QiniuStorage.new(access_key: ENV["QINIU_ACCESS_KEY"], secret_key: ENV["QINIU_SECRET_KEY"])
	end

	def test_multipart_upload
		bucket = @client.bucket("test-#{SecureRandom.uuid}")
		bucket.create

		uploader = @client.uploader
		data = StringIO.new("1" * 1024 * 1024 * 4)
		file = uploader.multipart_upload(data, bucket, key: "digist_ones")
		file.chmime "text/plain"
		file.stat
		assert_equal "digist_ones", file.key
		assert_equal file.bucket, bucket
		assert_equal data.size, file.size
		assert_equal "text/plain", file.mime_type
		assert_equal file.etag, QiniuStorage.qetag(data)
	ensure
		bucket.drop
	end

	def test_resumable_upload
		bucket = @client.bucket("test-#{SecureRandom.uuid}")
		bucket.create

		uploader = @client.uploader
		data = StringIO.new("1" * 1024 * 1024 * 5)
		file = uploader.resumable_upload(data, bucket, key: "digist_ones", mime_type: "text/plain")
		file.stat
		assert_equal "digist_ones", file.key
		assert_equal file.bucket, bucket
		assert_equal data.size, file.size
		assert_equal "text/plain", file.mime_type
		assert_equal file.etag, QiniuStorage.qetag(data)
	ensure
		bucket.drop
	end
end
