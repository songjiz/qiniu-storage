require "test_helper"

class ZoneTest < Minitest::Test
  def test_zones_map
    assert_kind_of Hash, QiniuStorage::Zone.zones_map
    assert_equal 5, QiniuStorage::Zone.zones_map.size
    assert_equal QiniuStorage::Zone::LIST, QiniuStorage::Zone.zones_map.keys
  end
end