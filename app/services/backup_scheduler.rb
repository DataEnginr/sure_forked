class BackupScheduler
  JOB_NAME = "database_backup"

  def self.sync!
    Rails.logger.info("[BackupScheduler] backup_enabled=#{Setting.backup_enabled}, time=#{Setting.backup_time}")
    if Setting.backup_enabled?
      upsert_job
    else
      remove_job
    end
  end

  def self.upsert_job
    time_str = Setting.backup_time || "03:30"
    timezone_str = Setting.backup_timezone || "UTC"

    unless Setting.valid_backup_time?(time_str)
      Rails.logger.error("[BackupScheduler] Invalid time format: #{time_str}, using default 03:30")
      time_str = "03:30"
    end

    hour, minute = time_str.split(":").map(&:to_i)
    timezone = ActiveSupport::TimeZone[timezone_str] || ActiveSupport::TimeZone["UTC"]
    local_time = timezone.now.change(hour: hour, min: minute, sec: 0)
    utc_time = local_time.utc

    cron = "#{utc_time.min} #{utc_time.hour} * * *"

    job = Sidekiq::Cron::Job.create(
      name: JOB_NAME,
      cron: cron,
      class: "DatabaseBackupJob",
      queue: "scheduled",
      description: "Daily database backup uploaded to Google Drive"
    )

    if job.nil? || (job.respond_to?(:valid?) && !job.valid?)
      error_msg = job.respond_to?(:errors) ? job.errors.to_a.join(", ") : "unknown error"
      Rails.logger.error("[BackupScheduler] Failed to create cron job: #{error_msg}")
      raise StandardError, "Failed to create backup schedule: #{error_msg}"
    end

    Rails.logger.info("[BackupScheduler] Created cron job with schedule: #{cron} (#{time_str} #{timezone_str})")
    job
  end

  def self.remove_job
    if (job = Sidekiq::Cron::Job.find(JOB_NAME))
      job.destroy
    end
  end
end
