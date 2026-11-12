class PreciousAsset < ApplicationRecord
  include Accountable

  has_many :items, class_name: "PreciousAssetItem", dependent: :destroy
  alias_method :lots, :items

  class << self
    def classification
      "asset"
    end

    def icon
      "gem"
    end

    def color
      "var(--color-warning)"
    end
  end
end
