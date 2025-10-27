# frozen_string_literal: true

# This concern automatically adds status: :unprocessable_entity to render calls
# when the request is a form submission (POST/PATCH/PUT) and no status is explicitly provided.
# This prevents Turbo from throwing "Form responses must redirect to another location" error.
module TurboCompatibleRenderConcern
  extend ActiveSupport::Concern

  def render(*args, **options, &block)
    # Check if this is a mutating request (form submission)
    mutating_request = request.post? || request.patch? || request.put?

    # Check if status is not explicitly set
    status_not_set = options[:status].nil?

    # Check if we're rendering a template (not redirecting or sending data)
    rendering_template = !options.key?(:json) && !options.key?(:plain) && !options.key?(:body)

    # Auto-add unprocessable_entity status for Turbo compatibility
    if mutating_request && status_not_set && rendering_template
      options[:status] = :unprocessable_entity
    end

    super(*args, **options, &block)
  end
end
