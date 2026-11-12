require "test_helper"

class PreciousAssetWeightTest < ActiveSupport::TestCase
  test "converts supported gold units to grams" do
    assert_equal 10.to_d, PreciousAssetWeight.in_grams(10, "gram")
    assert_equal 1_000.to_d, PreciousAssetWeight.in_grams(1, "kilogram")
    assert_equal PreciousAssetWeight::TROY_OUNCE_GRAMS, PreciousAssetWeight.in_grams(1, "troy_ounce")
  end

  test "returns zero for missing or invalid values" do
    assert_equal 0.to_d, PreciousAssetWeight.in_grams(nil, "gram")
    assert_equal 0.to_d, PreciousAssetWeight.in_grams(1, "unknown")
  end
end
