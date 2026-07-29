class Settings::BackupsController < ApplicationController
  layout "settings"

  guard_feature unless: -> { self_hosted? }

  before_action :ensure_admin

  def show
    @breadcrumbs = [
      [ t("breadcrumbs.home"), root_path ],
      [ t(".title"), nil ]
    ]
  end

  def update
    if backup_params.key?(:backup_enabled)
      Setting.backup_enabled = backup_params[:backup_enabled] == "1"
    end

    if backup_params.key?(:backup_time)
      time_value = backup_params[:backup_time]
      unless Setting.valid_backup_time?(time_value)
        flash[:alert] = t(".invalid_backup_time")
        return redirect_to settings_backup_path
      end
      Setting.backup_time = time_value
      Setting.backup_timezone = current_user_timezone
    end

    if backup_params.key?(:backup_keep_days)
      days = backup_params[:backup_keep_days].to_i
      Setting.backup_keep_days = days.positive? ? days : 30
    end

    if backup_params.key?(:gdrive_folder_id)
      Setting.gdrive_folder_id = backup_params[:gdrive_folder_id].presence
    end

    update_encrypted_setting(:gdrive_service_account_json)

    sync_backup_scheduler!

    redirect_to settings_backup_path, notice: t(".success")
  end

  def run_now
    DatabaseBackupJob.perform_later
    redirect_to settings_backup_path, notice: t(".run_now_started")
  end

  private

    def backup_params
      return ActionController::Parameters.new unless params.key?(:setting)
      params.require(:setting).permit(
        :backup_enabled, :backup_time, :backup_keep_days,
        :gdrive_folder_id, :gdrive_service_account_json
      )
    end

    def ensure_admin
      redirect_to settings_backup_path, alert: t(".not_authorized") unless Current.user.admin?
    end

    def sync_backup_scheduler!
      BackupScheduler.sync!
    rescue StandardError => error
      Rails.logger.error("[BackupScheduler] Failed to sync scheduler: #{error.message}")
      flash[:alert] = t(".scheduler_sync_failed")
    end

    # Same masked-placeholder convention as Settings::HostingsController —
    # "********" means "leave the stored value untouched".
    def update_encrypted_setting(param_key)
      return unless backup_params.key?(param_key)
      value = backup_params[param_key].to_s.strip

      return if value == "********"

      Setting.public_send(:"#{param_key}=", value.presence)
    end

    def current_user_timezone
      Current.family&.timezone.presence || "UTC"
    end
end
