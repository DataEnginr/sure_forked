class RefreshPreciousAssetValuationJob < ApplicationJob
  retry_on PreciousAssetValuation::Error, ActiveRecord::RecordInvalid, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.record_terminal_failure(error)
  end

  def perform(account_id)
    @account_id = account_id
    @account = Account.active.find_by(id: account_id, accountable_type: "PreciousAsset")
    return unless @account

    Time.use_zone(ActiveSupport::TimeZone[@account.family.timezone.to_s] || Time.zone) do
      PreciousAssetValuation.new(account: @account).refresh!
    end
  end

  def record_terminal_failure(error)
    DebugLogEntry.capture(
      category: "precious_asset_valuation", level: "error", message: error.message,
      source: self.class.name, family: @account&.family, account: @account,
      metadata: { account_id: @account_id }
    )
  end
end
