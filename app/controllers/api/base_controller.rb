class Api::BaseController < ActionController::API
  # ActionController::API doesn't include CSRF protection by default

  # Use unified error handling from FriendlyErrorHandlingConcern
  include FriendlyErrorHandlingConcern
end
