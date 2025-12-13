# Broadcast Rails logger errors to frontend via ActionCable (development only)
# Only broadcasts errors from app/ directory (business logic)
# Frontend error_handler will deduplicate automatically

if Rails.env.development?
  Rails.application.config.after_initialize do
    class << Rails.logger
      alias_method :original_error, :error unless method_defined?(:original_error)

      # Support formats:
      # Rails.logger.error("message")                    - broadcasts
      # Rails.logger.error("message", broadcast: false)  - no broadcast
      # Rails.logger.error(exception)                    - broadcasts
      # Rails.logger.error(exception, broadcast: false)  - no broadcast
      # Rails.logger.error { "message" }                 - broadcasts
      def error(message = nil, broadcast: true, &block)
        result = original_error(message, &block)
        actual_message = message || block&.call

        if broadcast && actual_message.present? && from_app_directory?
          broadcast_to_frontend(actual_message)
        end

        result
      end

      private

      # Check if error is from app/ directory (only check first 5 callers)
      def from_app_directory?
        caller.first(5).any? { |line| line.include?('/app/') }
      end

      def broadcast_to_frontend(message)
        # Build error data
        error_data = if message.is_a?(Exception)
          {
            message: "#{message.class}: #{message.message}",
            backtrace: Rails.backtrace_cleaner.clean(message.backtrace || []).first(10).join("\n"),
            timestamp: Time.current.iso8601,
            source: 'rails_logger',
            level: 'error'
          }
        else
          # For string messages, capture caller info (skip first line which is this file)
          caller_info = caller[1..-1] || []
          cleaned_backtrace = Rails.backtrace_cleaner.clean(caller_info)

          {
            message: filter_sensitive_data(message.to_s),
            backtrace: cleaned_backtrace.first(10).join("\n"),
            timestamp: Time.current.iso8601,
            source: 'rails_logger',
            level: 'error'
          }
        end

        # Broadcast to frontend
        Turbo::StreamsChannel.broadcast_render_to(
          "system_monitor",
          inline: "<turbo-stream action='report_logger_error' data-error='<%= error_data.to_json.gsub(\"'\", \"&#39;\") %>'></turbo-stream>",
          locals: { error_data: error_data }
        )
      rescue => e
        original_error("Failed to broadcast: #{e.message}")
      end

      def filter_sensitive_data(message)
        message.gsub(/password[=:]\s*\S+/i, 'password=***')
               .gsub(/token[=:]\s*\S+/i, 'token=***')
               .gsub(/secret[=:]\s*\S+/i, 'secret=***')
      end
    end
  end
end
