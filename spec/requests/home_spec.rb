require 'rails_helper'

# IMPORTANT: Demo File Management in Tests
# - If app/views/shared/demo.html.erb exists but app/views/home/index.html.erb exists,
#   demo.html.erb should be deleted immediately as it's only for early development
# - Tests should verify real homepage functionality, not demo placeholder content
# - Demo contains fake data and should not be referenced in production feature tests

RSpec.describe "Home", type: :request do
  describe "GET /" do
    it "returns http success" do
      get root_path
      expect(response).to be_success_with_view_check('index')
    end

    it "should not have demo.html.erb when home/index.html.erb exists" do
      index_template_path = Rails.root.join('app', 'views', 'home', 'index.html.erb')
      demo_template_path = Rails.root.join('app', 'views', 'shared', 'demo.html.erb')

      if File.exist?(index_template_path)
        expect(File.exist?(demo_template_path)).to be_falsey,
          "Demo file should be deleted when real homepage exists. Found both #{index_template_path} and #{demo_template_path}"
      end
    end

    it "home views should not contain nav tags directly" do
      # Navigation should be in shared/_navbar.html.erb, not in home views
      index_template_path = Rails.root.join('app', 'views', 'home', 'index.html.erb')

      if File.exist?(index_template_path)
          content = File.read(index_template_path)
          expect(content).not_to match(/<nav[\s>]/i),
            "home/index.html.erb should not contain <nav> tags. " \
            "Navigation should be implemented in app/views/shared/_navbar.html.erb instead. " \
      end
    end

    it "should customize appname from default value" do
      appname = Rails.application.config.x.appname
      expect(appname).not_to eq("ClackyAPP"),
        "Please customize your application name in config/application.rb. " \
        "Change config.x.appname from the default 'ClackyAPP' to your own app name."
    end

    it "should not contain demo-style placeholder links or forms in view file" do
      index_template_path = Rails.root.join('app', 'views', 'home', 'index.html.erb')

      if File.exist?(index_template_path)
        content = File.read(index_template_path)
        doc = Nokogiri::HTML(content)

        # Check for placeholder links in HTML
        bad_links = doc.css('a[href="#"], a[href="#!"], a[href^="javascript:"]')
        expect(bad_links).to be_empty,
          "Found #{bad_links.size} demo placeholder link(s) in home/index.html.erb: #{bad_links.map { |l| l.to_html.truncate(80) }.join(', ')}. Use real Rails routes (like rooms_path) instead of copying from demo.html.erb."

        # Check for placeholder links in ERB code (link_to or link helpers)
        erb_bad_links = []
        content.each_line.with_index do |line, index|
          line_number = index + 1
          # Match link_to 'text', '#' or link 'text', '#'
          if line.match?(/<%=?\s*(link_to|link)\s+['"][^'"]*['"]\s*,\s*['"]#['"]\s*/)
            erb_bad_links << { line: line_number, content: line.strip }
          end
        end

        expect(erb_bad_links).to be_empty,
          "Found #{erb_bad_links.size} ERB link helper(s) with placeholder href '#' in home/index.html.erb:\n" +
          erb_bad_links.map { |l| "  Line #{l[:line]}: #{l[:content]}" }.join("\n") +
          "\nUse real Rails routes (like rooms_path) instead of '#'."

        # Check for forms without action or with placeholder action
        bad_forms = doc.css('form:not([action]), form[action="#"], form[action=""], form[action^="javascript:"]')
        expect(bad_forms).to be_empty,
          "Found #{bad_forms.size} demo placeholder form(s) in home/index.html.erb. Please implement real business logic using Rails form helpers (form_with). WARNING: Never nest button_to inside a form element."
      end
    end
  end
end
