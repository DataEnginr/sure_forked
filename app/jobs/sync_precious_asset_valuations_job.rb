# Refresh Gems and Bullion accounts; brokerage investments use their providers.
class SyncPreciousAssetValuationsJob < ApplicationJob
  queue_as :scheduled
  sidekiq_options lock: :until_executed, on_conflict: :log

  def perform
    Account.active.where(accountable_type: "PreciousAsset").find_each do |account|
      RefreshPreciousAssetValuationJob.perform_later(account.id)
    end
  end
end
