# Orchestrates a single database backup run:
#   1. Dumps the app's actual Postgres database with `pg_dump` — the exact
#      same tool/data the compose.yml `backup` service (postgres-backup-local)
#      uses — using the same connection details Rails itself connects with.
#   2. Gzips the dump.
#   3. Uploads it to Google Drive via Backup::GoogleDriveUploader.
#   4. Prunes Drive backups older than Setting.backup_keep_days.
#   5. Records the outcome on Setting (last_backup_at / status / error / size)
#      so the Settings UI can display it.
#
# Runs inside the web/worker container, which already ships `postgresql-client`
# (see Dockerfile), so `pg_dump` is available without any extra image changes.
module Backup
  class Runner
    FILENAME_PREFIX = "sure_backup_"

    Result = Struct.new(:success?, :error, :size_bytes, keyword_init: true)

    def run!
      validate_config!

      dump_path = dump_database!
      filename = "#{FILENAME_PREFIX}#{Time.current.utc.strftime('%Y-%m-%d_%H-%M-%S')}.sql.gz"
      size_bytes = File.size(dump_path)

      uploader.upload(dump_path, filename: filename)
      prune_old_backups!

      record_success!(size_bytes)
      Result.new(success?: true, size_bytes: size_bytes)
    rescue => e
      Rails.logger.error("[Backup::Runner] Backup failed: #{e.class}: #{e.message}")
      record_failure!(e.message)
      Result.new(success?: false, error: e.message)
    ensure
      File.delete(dump_path) if dump_path && File.exist?(dump_path)
    end

    private

      def validate_config!
        if Setting.gdrive_folder_id.blank? || Setting.gdrive_service_account_json.blank?
          raise Backup::GoogleDriveUploader::ConfigurationError,
                "Google Drive folder ID and service account credentials must be configured in Settings > Backups"
        end
      end

      # Dumps the database Rails is actually connected to (same DB the app
      # and the compose `backup` service use), gzips the output, and writes
      # it to a Tempfile. Returns the Tempfile path.
      def dump_database!
        db_config = ActiveRecord::Base.connection_db_config.configuration_hash

        tempfile = Tempfile.new([ "sure_backup", ".sql.gz" ], binmode: true)

        env = {
          "PGPASSWORD" => db_config[:password].to_s
        }

        cmd = [
          "pg_dump",
          "-h", db_config[:host].to_s,
          "-p", db_config[:port].to_s,
          "-U", db_config[:username].to_s,
          "-d", db_config[:database].to_s,
          "--format=plain",
          "--no-owner",
          "--no-privileges"
        ]

        Zlib::GzipWriter.open(tempfile.path) do |gz|
          Open3.popen3(env, *cmd) do |stdin, stdout, stderr, wait_thr|
            stdin.close
            IO.copy_stream(stdout, gz)
            err = stderr.read
            unless wait_thr.value.success?
              raise "pg_dump failed: #{err.presence || 'unknown error'}"
            end
          end
        end

        tempfile.path
      end

      def prune_old_backups!
        keep_days = Setting.backup_keep_days.to_i
        keep_days = 30 if keep_days <= 0
        cutoff = keep_days.days.ago

        uploader.list(name_prefix: FILENAME_PREFIX).each do |file|
          created_at = Time.zone.parse(file.created_time.to_s) rescue nil
          next unless created_at && created_at < cutoff

          uploader.delete(file.id)
          Rails.logger.info("[Backup::Runner] Pruned old backup from Drive: #{file.name}")
        end
      end

      def record_success!(size_bytes)
        Setting.last_backup_at = Time.current.utc.iso8601
        Setting.last_backup_status = "success"
        Setting.last_backup_error = nil
        Setting.last_backup_size_bytes = size_bytes
      end

      def record_failure!(message)
        Setting.last_backup_at = Time.current.utc.iso8601
        Setting.last_backup_status = "failed"
        Setting.last_backup_error = message.to_s.truncate(500)
      end

      def uploader
        @uploader ||= Backup::GoogleDriveUploader.new(
          folder_id: Setting.gdrive_folder_id,
          service_account_json: Setting.gdrive_service_account_json
        )
      end
  end
end
