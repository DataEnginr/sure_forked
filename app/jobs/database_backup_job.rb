# Runs a full database backup + Google Drive upload (see Backup::Runner).
# Triggered either by BackupScheduler's daily cron entry, or on-demand from
# Settings > Backups ("Run backup now").
class DatabaseBackupJob < ApplicationJob
  queue_as :scheduled

  # Backups are heavy, sequential, and shouldn't pile up if one is slow —
  # skip a scheduled run if one is already in flight rather than queuing more.
  sidekiq_options lock: :until_executed, on_conflict: :log

  def perform
    result = Backup::Runner.new.run!

    unless result.success?
      Rails.logger.error("[DatabaseBackupJob] Backup failed: #{result.error}")
    end
  end
end
