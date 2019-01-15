require "test_helper"

class QiniuStorageTest < Minitest::Test
  def test_gem_version_number
    assert_equal QiniuStorage::VERSION, "0.1.0"
	end
end
