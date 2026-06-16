# frozen_string_literal: true

Rails.application.config.to_prepare do
  ActiveSupport.on_load(:active_storage_blob) do
    after_create_commit do
      AiImageDetectionJob.perform_later(self) if content_type&.start_with?("image/")
    end
  end
end
