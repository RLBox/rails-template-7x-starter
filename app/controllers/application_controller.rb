class ApplicationController < ActionController::Base
  # Allow browsers with broader compatibility
  allow_browser versions: {
    chrome: 80,
    firefox: 75,
    safari: 13,
    edge: 80,
    opera: 67
  }

  include FriendlyErrorHandlingConcern
  include DevelopmentCsrfBypassConcern
  include TurboCompatibleRenderConcern

end
