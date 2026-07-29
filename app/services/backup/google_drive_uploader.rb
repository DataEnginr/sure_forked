# Thin wrapper around the Google Drive API (google-apis-drive_v3 gem) used to
# upload database backups to a shared Google Drive folder via a service
# account.
#
# IMPORTANT — Google Drive service account quota:
# A service account has no personal Drive storage of its own. For it to be
# able to write files, the *destination folder* must be either:
#   a) a folder inside a Shared Drive (Google Workspace), with the service
#      account added as a member/Content Manager, OR
#   b) a regular folder in a personal Google Drive account, shared with the
#      service account's email address (found in the JSON key as
#      "client_email") with "Editor" access.
# Without this, uploads will fail with a storage-quota error.
module Backup
  class GoogleDriveUploader
    class ConfigurationError < StandardError; end
    class UploadError < StandardError; end

    SCOPE = "https://www.googleapis.com/auth/drive"

    def initialize(folder_id:, service_account_json:)
      raise ConfigurationError, "Google Drive folder ID is not configured" if folder_id.blank?
      raise ConfigurationError, "Google Drive service account JSON is not configured" if service_account_json.blank?

      @folder_id = folder_id
      @service_account_json = service_account_json
    end

    # Uploads a local file to the configured Drive folder.
    # Returns the created Drive file's ID.
    def upload(local_path, filename:, content_type: "application/gzip")
      file_metadata = Google::Apis::DriveV3::File.new(
        name: filename,
        parents: [ @folder_id ]
      )

      result = service.create_file(
        file_metadata,
        fields: "id, name, size, createdTime",
        upload_source: local_path,
        content_type: content_type
      )

      result
    rescue Google::Apis::Error => e
      raise UploadError, "Google Drive upload failed: #{e.message}"
    end

    # Lists backup files in the folder matching a filename prefix, newest first.
    def list(name_prefix:)
      query = "'#{@folder_id}' in parents and name contains '#{name_prefix}' and trashed = false"

      files = []
      page_token = nil

      loop do
        response = service.list_files(
          q: query,
          fields: "nextPageToken, files(id, name, createdTime, size)",
          order_by: "createdTime desc",
          page_token: page_token,
          spaces: "drive"
        )
        files.concat(response.files || [])
        page_token = response.next_page_token
        break if page_token.blank?
      end

      files
    rescue Google::Apis::Error => e
      raise UploadError, "Google Drive list failed: #{e.message}"
    end

    # Permanently deletes a Drive file by ID (used for retention pruning).
    def delete(file_id)
      service.delete_file(file_id)
    rescue Google::Apis::Error => e
      raise UploadError, "Google Drive delete failed: #{e.message}"
    end

    private

      def service
        @service ||= begin
          svc = Google::Apis::DriveV3::DriveService.new
          svc.client_options.application_name = "Sure Database Backup"
          svc.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
            json_key_io: StringIO.new(@service_account_json),
            scope: SCOPE
          )
          svc
        end
      end
  end
end
