require "test_helper"

class ClientTest < Minitest::Test
	def setup
    @client = QiniuStorage.new(access_key: ENV["QINIU_ACCESS_KEY"], secret_key: ENV["QINIU_SECRET_KEY"])
	end

	def test_access_key_and_secret_key
		assert_equal @client.access_key, ENV["QINIU_ACCESS_KEY"]
		assert_equal @client.secret_key, ENV["QINIU_SECRET_KEY"]
	end

	def test_buckets
		buckets = @client.buckets
		assert_kind_of Array, buckets
	end
end