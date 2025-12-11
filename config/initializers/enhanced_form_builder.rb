# Set EnhancedFormBuilder as the default form builder for the application
# This ensures all form_with and form_for calls automatically use our enhanced builder
# unless explicitly overridden with builder: option

Rails.application.config.to_prepare do
  ActionView::Base.default_form_builder = EnhancedFormBuilder
end
