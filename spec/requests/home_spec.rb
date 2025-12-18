require 'rails_helper'

# IMPORTANT: Demo File Management in Tests
# - If app/views/shared/demo.html.erb exists but app/views/home/index.html.erb exists,
#   demo.html.erb should be deleted immediately as it's only for early development
# - Tests should verify real homepage functionality, not demo placeholder content
# - Demo contains fake data and should not be referenced in production feature tests

RSpec.describe "Home", type: :request do
  describe "GET /" do
    it "returns http success and validates page quality" do
      get root_path
      expect(response).to be_success_with_view_check('index')

      # Skip quality checks if redirected (no HTML content to validate)
      return if response.redirect?

      doc = Nokogiri::HTML(response.body)

      # Check 1: No duplicate headers (navigation bars)
      nav_count = doc.css('nav').count

      # Find headers with auth links: sign_in/sign_out, login/logout, or session (any one counts)
      nav_headers = doc.css('body header, main header').reject do |header|
        header.ancestors.any? { |a| %w[article section].include?(a.name) }
      end.select do |header|
        header.css('a[href*="sign_in"], a[href*="sign_out"], a[href*="login"], a[href*="logout"], a[href*="session"]').any?
      end

      total_navigation = nav_count + nav_headers.count
      expect(total_navigation).to be <= 1,
        "Found #{total_navigation} navigation elements (#{nav_count} <nav> + #{nav_headers.count} header). " \
        "Remove duplicate header from view as shared/_navbar.html.erb is automatically rendered in the layout."

      # Check 2: No demo placeholder links
      bad_links = doc.css('a[href="#"], a[href="#!"], a[href^="javascript:"]')
      expect(bad_links).to be_empty,
        "Found #{bad_links.size} placeholder link(s). Replace them with real routes:\n" \
        "  - Static pages : create new page with home controller\n" \
        "  - Functional links: use existing route helpers"

      # Check 3: No placeholder forms
      bad_forms = doc.css('form:not([action]), form[action="#"], form[action=""], form[action^="javascript:"]')
      expect(bad_forms).to be_empty,
        "Found #{bad_forms.size} placeholder form(s). Use Rails form helpers (form_with) with real routes."
    end

    it "should not have demo.html.erb when home/index.html.erb exists" do
      index_template_path = Rails.root.join('app', 'views', 'home', 'index.html.erb')
      demo_template_path = Rails.root.join('app', 'views', 'shared', 'demo.html.erb')

      if File.exist?(index_template_path)
        expect(File.exist?(demo_template_path)).to be_falsey,
          "Demo served as HTML structure reference and must be deleted now. Remove #{demo_template_path} since #{index_template_path} exists."
      end
    end

    it "should customize appname from default value" do
      appname = Rails.application.config.x.appname
      expect(appname).not_to eq("ClackyAPP"),
        "Please customize your application name in config/application.rb. " \
        "Change config.x.appname from the default 'ClackyAPP' to your own app name."
    end

  end
end
