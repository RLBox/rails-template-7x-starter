require 'rails_helper'

RSpec.describe 'Stimulus Validation', type: :system do
  include StimulusValidationHelpers

  # Initialize pipeline once for all tests
  let(:pipeline) { StimulusValidationPipeline.new }
  let(:controller_data) { pipeline.controller_data }
  let(:view_files) { pipeline.view_files }
  let(:partial_parent_map) { pipeline.partial_parent_map }
  let(:controllers_dir) { Rails.root.join('app/javascript/controllers') }

  # Delegate to pipeline helper methods
  def get_controllers_from_parents(partial_path)
    pipeline.get_controllers_from_parents(partial_path)
  end

  def contains_controller_in_ast?(node, controller_name)
    erb_parser = ErbAstParser.new("")
    erb_parser.send(:contains_controller_in_ast?, node, controller_name)
  end

  describe 'Core Validation: Targets and Actions' do
    it 'validates that controller targets exist in HTML and actions have methods' do
      target_errors = []
      target_scope_errors = []
      action_errors = []
      scope_errors = []
      registration_errors = []
      value_errors = []
      outlet_errors = []

      view_files.each do |view_file|
        content = File.read(view_file)
        relative_path = view_file.sub(Rails.root.to_s + '/', '')

        doc = Nokogiri::HTML::DocumentFragment.parse(content)

        doc.css('[data-controller]').each do |controller_element|
          controllers = controller_element['data-controller'].split(/\s+/)

          controllers.each do |controller_name|
            controller_name = controller_name.strip

            # Check if controller exists
            unless controller_data.key?(controller_name)
              registration_errors << {
                controller: controller_name,
                file: relative_path,
                suggestion: "Create controller file: rails generate stimulus_controller #{controller_name.gsub('-', '_')}"
              }
              next # Skip further validation if controller doesn't exist
            end

            controller_data[controller_name][:targets].each do |target|
              # Skip optional targets (those with hasXXXTarget declaration)
              next if controller_data[controller_name][:optional_targets].include?(target)

              # Skip targets with stimulus-validator: disable-next-line comment
              next if controller_data[controller_name][:targets_with_skip].include?(target)

              target_found_in_scope = false

              # 1. Check if controller element itself has the target (HTML attribute)
              if controller_element["data-#{controller_name}-target"]&.include?(target)
                target_found_in_scope = true
              end

              # 2. If not found on controller element, look inside it (HTML descendants)
              unless target_found_in_scope
                target_selector = "[data-#{controller_name}-target*='#{target}']"
                target_found_in_scope = controller_element.css(target_selector).any?
              end

              # 3. Use AST parser to find targets in ERB blocks within controller scope
              unless target_found_in_scope
                erb_parser = ErbAstParser.new(content)
                erb_targets = erb_parser.find_stimulus_targets(controller_name, target)

                # Check if any ERB target is within the controller scope
                erb_targets.each do |erb_target|
                  # For now, consider ERB targets found if they exist anywhere in the file
                  # TODO: Implement proper scope checking for ERB blocks
                  target_found_in_scope = true
                  break
                end
              end

              unless target_found_in_scope
                # Check if target exists anywhere else in the file (out of scope)
                target_exists_elsewhere = false

                # Check HTML elements outside current controller scope
                doc.css("[data-#{controller_name}-target*='#{target}']").each do |element|
                  # Check if this element is outside the current controller scope
                  is_outside_scope = true
                  element.ancestors.each do |ancestor|
                    if ancestor == controller_element
                      is_outside_scope = false
                      break
                    end
                  end

                  if is_outside_scope
                    target_exists_elsewhere = true
                    break
                  end
                end

                # Check ERB blocks for targets outside scope
                unless target_exists_elsewhere
                  erb_parser = ErbAstParser.new(content)
                  erb_targets = erb_parser.find_stimulus_targets(controller_name, target)
                  # If ERB targets exist, they might be outside scope
                  # For simplicity, we consider them as potentially out of scope
                end

                if target_exists_elsewhere
                  # Target exists but is out of scope
                  target_scope_errors << {
                    controller: controller_name,
                    target: target,
                    file: relative_path,
                    error_type: "out_of_scope",
                    suggestion: "Move <div data-#{controller_name}-target=\"#{target}\">...</div> inside controller scope or move controller definition to parent element"
                  }
                else
                  # Target doesn't exist at all
                  target_errors << {
                    controller: controller_name,
                    target: target,
                    file: relative_path,
                    suggestion: "Add <div data-#{controller_name}-target=\"#{target}\">...</div> within controller scope or use ERB syntax: data: { \"#{controller_name}-target\" => \"#{target}\" }"
                  }
                end
              end
            end

            # Check for missing or incorrectly formatted values using AST parser
            controller_data[controller_name][:values].each do |value_name|
              # Skip values with default values
              next if controller_data[controller_name][:values_with_defaults].include?(value_name)

              # Skip values with stimulus-validator: disable-next-line comment
              next if controller_data[controller_name][:values_with_skip].include?(value_name)

              kebab_value_name = value_name.gsub(/([a-z])([A-Z])/, '\1-\2').downcase
              expected_attr = "data-#{controller_name}-#{kebab_value_name}-value"
              value_found = false

              # 1. Check HTML attributes on controller element
              if controller_element.has_attribute?(expected_attr)
                value_found = true
              end

              # 2. Use AST parser to find values in ERB blocks
              unless value_found
                erb_parser = ErbAstParser.new(content)
                erb_values = erb_parser.find_stimulus_values(controller_name, value_name)

                if erb_values.any?
                  value_found = true
                end
              end

              # 3. Check for common mistakes using AST and string detection
              unless value_found
                common_mistakes = [
                  "data-#{value_name}",
                  "data-#{controller_name}-#{value_name}",
                  "data-#{controller_name}-#{kebab_value_name}",
                  "data-#{value_name}-value"
                ]

                # Filter out standard Stimulus attributes
                stimulus_standard_attrs = %w[data-controller data-action data-target]
                common_mistakes = common_mistakes.reject { |attr|
                  stimulus_standard_attrs.any? { |std_attr| attr.start_with?(std_attr) }
                }

                found_mistakes = common_mistakes.select { |attr|
                  controller_element.has_attribute?(attr) || content.include?(attr)
                }

                if found_mistakes.any?
                  value_errors << {
                    controller: controller_name,
                    value: value_name,
                    file: relative_path,
                    expected: expected_attr,
                    found: found_mistakes.first,
                    suggestion: "Change '#{found_mistakes.first}' to '#{expected_attr}'"
                  }
                else
                  value_errors << {
                    controller: controller_name,
                    value: value_name,
                    file: relative_path,
                    expected: expected_attr,
                    found: nil,
                    suggestion: "Add #{expected_attr}=\"...\" to controller element"
                  }
                end
              end
            end

            # Check for outlet attributes
            controller_data[controller_name][:outlets].each do |outlet_name|
              outlet_attr = "data-#{controller_name}-#{outlet_name.gsub('_', '-')}-outlet"

              # Check if outlet attribute exists
              unless controller_element.has_attribute?(outlet_attr)
                # Check for common mistakes
                wrong_attr_with_value = "#{outlet_attr}-value"

                if controller_element.has_attribute?(wrong_attr_with_value)
                  outlet_errors << {
                    controller: controller_name,
                    outlet: outlet_name,
                    selector: nil,
                    file: relative_path,
                    error_type: 'wrong_attribute_name',
                    found_attr: wrong_attr_with_value,
                    expected_attr: outlet_attr,
                    suggestion: "Change '#{wrong_attr_with_value}' to '#{outlet_attr}' (remove -value suffix)"
                  }
                else
                  outlet_errors << {
                    controller: controller_name,
                    outlet: outlet_name,
                    selector: nil,
                    file: relative_path,
                    error_type: 'missing_outlet',
                    expected_attr: outlet_attr,
                    suggestion: "Add #{outlet_attr}=\"[data-controller='...']\" to element"
                  }
                end
                next
              end

              outlet_selector = controller_element[outlet_attr]

              # Validate that outlet selector uses [data-controller] pattern
              unless outlet_selector.match?(/^\[data-controller/)
                outlet_errors << {
                  controller: controller_name,
                  outlet: outlet_name,
                  selector: outlet_selector,
                  file: relative_path,
                  error_type: 'invalid_selector',
                  suggestion: "Outlet selector must use [data-controller] pattern, found: '#{outlet_selector}'"
                }
                next
              end

              # Check if target element exists
              target_element = doc.css(outlet_selector).first
              if target_element.nil?
                outlet_errors << {
                  controller: controller_name,
                  outlet: outlet_name,
                  selector: outlet_selector,
                  file: relative_path,
                  error_type: 'target_not_found',
                  suggestion: "No element found matching selector '#{outlet_selector}'"
                }
              end
            end
          end
        end

        # Parse both HTML data-action attributes and ERB data: { action: } syntax
        all_actions = []

        # Parse HTML data-action attributes
        doc.css('[data-action]').each do |action_element|
          action_value = action_element['data-action']
          parsed_actions = parse_action_string(action_value)
          parsed_actions.each do |action_info|
            all_actions << {
              element: action_element,
              action: action_info[:action],
              event: action_info[:event],
              controller: action_info[:controller],
              method: action_info[:method]
            }
          end
        end

        # Parse ERB data: { action: } syntax
        erb_actions = parse_erb_actions(content, relative_path)
        erb_actions.each do |action_info|
          all_actions << action_info
        end

        all_actions.each do |action_info|
          action_element = action_info[:element]
          controller_name = action_info[:controller]
          method_name = action_info[:method]
          action = action_info[:action]
          source = action_info[:source]

          # For ERB actions, check if controller scope actually includes the action
          if source == 'erb_ast'
            controller_scope = false

            # Use proper scope checking for ERB actions
            controller_scope = check_erb_action_scope(action_info, content, relative_path)

            # Check parent files for partials
            if !controller_scope && relative_path.include?('_')
              parent_controllers = get_controllers_from_parents(relative_path)
              if parent_controllers.include?(controller_name)
                controller_scope = true
              end
            end
          else
            # For HTML data-action attributes
            controller_scope = false

            # Check if element itself has the controller
            if action_element['data-controller']&.include?(controller_name)
              controller_scope = action_element
            else
              # Check ancestors for the controller (correct way)
              action_element.ancestors.each do |ancestor|
                if ancestor['data-controller']&.include?(controller_name)
                  controller_scope = ancestor
                  break
                end
              end
            end

            if !controller_scope && relative_path.include?('_')
              parent_controllers = get_controllers_from_parents(relative_path)
              if parent_controllers.include?(controller_name)
                controller_scope = true
              end
            end
          end

          unless controller_scope
            # Check if controller exists anywhere in the file using AST parsing
            controller_exists_in_file = false

            # Check HTML data-controller attributes
            doc.css('[data-controller]').each do |element|
              if element['data-controller'].split(/\s+/).include?(controller_name)
                controller_exists_in_file = true
                break
              end
            end

            # Check ERB blocks for controller definitions using AST
            unless controller_exists_in_file
              erb_parser = ErbAstParser.new(content)
              erb_parser.instance_variable_get(:@erb_blocks).each do |block|
                next unless block[:code].include?('data') && block[:code].include?('controller')

                begin
                  processed_code = erb_parser.send(:preprocess_erb_code, block[:code])
                  ast = Parser::CurrentRuby.parse(processed_code)
                  if contains_controller_in_ast?(ast, controller_name)
                    controller_exists_in_file = true
                    break
                  end
                rescue
                  # Skip unparseable blocks
                end
              end
            end

            if controller_exists_in_file
              # Controller exists but out of scope
              if relative_path.include?('_')
                suggestion = "Controller '#{controller_name}' exists but action is out of scope - move action within controller scope or define controller in parent template"
              else
                suggestion = "Controller '#{controller_name}' exists but action is out of scope - move action within <div data-controller=\"#{controller_name}\">...</div>"
              end
              error_type = "out_of_scope"
            else
              # Controller doesn't exist in file at all
              if relative_path.include?('_')
                suggestion = "Controller '#{controller_name}' should be defined in parent template or wrap with <div data-controller=\"#{controller_name}\">...</div>"
              else
                suggestion = "Wrap with <div data-controller=\"#{controller_name}\">...</div>"
              end
              error_type = "missing_controller"
            end

            scope_errors << {
              action: action,
              controller: controller_name,
              file: relative_path,
              is_partial: relative_path.include?('_'),
              parent_files: partial_parent_map[relative_path] || [],
              suggestion: suggestion,
              source: source,
              error_type: error_type
            }
            next
          end

          if controller_data.key?(controller_name)
            # Check if method exists
            unless controller_data[controller_name][:methods].include?(method_name)
              action_errors << {
                action: action,
                controller: controller_name,
                method: method_name,
                file: relative_path,
                available_methods: controller_data[controller_name][:methods],
                suggestion: "Add method '#{method_name}(): void { }' to #{controller_name} controller",
                source: source
              }
            end
          end
        end
      end

      # Remove duplicates from registration errors
      registration_errors = registration_errors.uniq { |error| [error[:controller], error[:file]] }

      total_errors = target_errors.length + target_scope_errors.length + action_errors.length + scope_errors.length + registration_errors.length + value_errors.length + outlet_errors.length

      puts "\n🔍 Simple Stimulus Validation Results:"
      puts "   📁 Scanned: #{view_files.length} views, #{controller_data.keys.length} controllers"

      if total_errors == 0
        puts "   ✅ All validations passed!"
      else
        puts "\n   ❌ Found #{total_errors} issue(s):"

        if registration_errors.any?
          puts "\n   📝 Missing Controllers (#{registration_errors.length}):"
          registration_errors.each do |error|
            puts "     • #{error[:controller]} controller not found in #{error[:file]}"
          end
        end

        if target_errors.any?
          puts "\n   🎯 Missing Targets (#{target_errors.length}):"
          target_errors.each do |error|
            puts "     • #{error[:controller]}:#{error[:target]} missing in #{error[:file]}"
          end
        end

        if target_scope_errors.any?
          puts "\n   🎯 Target Out of Scope Errors (#{target_scope_errors.length}):"
          target_scope_errors.each do |error|
            puts "     • #{error[:controller]}:#{error[:target]} exists but is out of controller scope in #{error[:file]}"
          end
        end

        if target_errors.any? || target_scope_errors.any?
          puts "   💡 If you've confirmed the target is handled dynamically or in another way, add '// stimulus-validator: disable-next-line' before the target declaration."
        end

        if value_errors.any?
          puts "\n   📋 Value Errors (#{value_errors.length}):"
          value_errors.each do |error|
            if error[:found]
              puts "     • #{error[:controller]}:#{error[:value]} incorrect format '#{error[:found]}' in #{error[:file]}, expected '#{error[:expected]}'"
            else
              puts "     • #{error[:controller]}:#{error[:value]} missing in #{error[:file]}"
            end
          end
          puts "   💡 If you've confirmed the value is handled dynamically or has a default, add '// stimulus-validator: disable-next-line' before the value declaration."
        end

        if outlet_errors.any?
          puts "\n   🔌 Outlet Errors (#{outlet_errors.length}):"
          outlet_errors.each do |error|
            case error[:error_type]
            when 'wrong_attribute_name'
              puts "     • #{error[:controller]}:#{error[:outlet]} wrong attribute name '#{error[:found_attr]}' in #{error[:file]}, expected '#{error[:expected_attr]}'"
            when 'missing_outlet'
              puts "     • #{error[:controller]}:#{error[:outlet]} missing outlet attribute '#{error[:expected_attr]}' in #{error[:file]}"
            when 'invalid_selector'
              puts "     • #{error[:controller]}:#{error[:outlet]} uses invalid selector '#{error[:selector]}' in #{error[:file]}"
            when 'target_not_found'
              puts "     • #{error[:controller]}:#{error[:outlet]} target not found for selector '#{error[:selector]}' in #{error[:file]}"
            end
          end
        end

        if scope_errors.any?
          out_of_scope_errors = scope_errors.select { |e| e[:error_type] == "out_of_scope" }
          missing_controller_errors = scope_errors.select { |e| e[:error_type] == "missing_controller" }

          if out_of_scope_errors.any?
            puts "\n   🚨 Out of Scope Errors (#{out_of_scope_errors.length}):"
            out_of_scope_errors.each do |error|
              if error[:is_partial] && error[:parent_files].any?
                puts "     • #{error[:action]} controller exists but action is out of scope in #{error[:file]} (partial rendered in: #{error[:parent_files].join(', ')})"
              else
                puts "     • #{error[:action]} controller exists but action is out of scope in #{error[:file]}"
              end
            end
          end

          if missing_controller_errors.any?
            puts "\n   🚨 Missing Controller Scope (#{missing_controller_errors.length}):"
            missing_controller_errors.each do |error|
              if error[:is_partial] && error[:parent_files].any?
                puts "     • #{error[:action]} needs controller scope in #{error[:file]} (partial rendered in: #{error[:parent_files].join(', ')})"
              else
                puts "     • #{error[:action]} needs controller scope in #{error[:file]}"
              end
            end
          end
        end

        if action_errors.any?
          puts "\n   ⚠️  Method Errors (#{action_errors.length}):"
          action_errors.each do |error|
            puts "     • #{error[:controller]}##{error[:method]} not found in #{error[:file]}"
          end
        end

        error_details = []

        registration_errors.each do |error|
          error_details << "Missing controller: #{error[:controller]} in #{error[:file]} - #{error[:suggestion]}"
        end

        target_errors.each do |error|
          error_details << "Missing target: #{error[:controller]}:#{error[:target]} in #{error[:file]} - #{error[:suggestion]}"
        end

        target_scope_errors.each do |error|
          error_details << "Target out of scope: #{error[:controller]}:#{error[:target]} in #{error[:file]} - #{error[:suggestion]}"
        end

        value_errors.each do |error|
          error_details << "Value error: #{error[:controller]}:#{error[:value]} in #{error[:file]} - #{error[:suggestion]}"
        end

        outlet_errors.each do |error|
          error_details << "Outlet error: #{error[:controller]}:#{error[:outlet]} in #{error[:file]} - #{error[:suggestion]}"
        end

        scope_errors.each do |error|
          if error[:error_type] == "out_of_scope"
            error_details << "Out of scope error: #{error[:action]} in #{error[:file]} - #{error[:suggestion]}"
          else
            error_details << "Scope error: #{error[:action]} in #{error[:file]} - #{error[:suggestion]}"
          end
        end

        action_errors.each do |error|
          error_details << "Method error: #{error[:controller]}##{error[:method]} in #{error[:file]} - #{error[:suggestion]}"
        end

        expect(total_errors).to eq(0), "Stimulus validation failed:\n#{error_details.join("\n")}"
      end
    end
  end

  describe 'Controller Analysis' do
    it 'provides controller coverage statistics' do
      total_controllers = controller_data.keys.length
      used_controllers = []

      view_files.each do |view_file|
        content = File.read(view_file)
        doc = Nokogiri::HTML::DocumentFragment.parse(content)

        controller_data.keys.each do |controller|
          # Check HTML data-controller attributes
          found_in_html = doc.css('[data-controller]').any? do |element|
            element['data-controller'].split(/\s+/).include?(controller)
          end

          # Check ERB blocks using AST
          found_in_erb = false
          unless found_in_html
            erb_parser = ErbAstParser.new(content)
            erb_parser.instance_variable_get(:@erb_blocks).each do |block|
              next unless block[:code].include?('data') && block[:code].include?('controller')

              begin
                processed_code = erb_parser.send(:preprocess_erb_code, block[:code])
                ast = Parser::CurrentRuby.parse(processed_code)
                if erb_parser.send(:contains_controller_in_ast?, ast, controller)
                  found_in_erb = true
                  break
                end
              rescue
                # Skip unparseable blocks
              end
            end
          end

          if found_in_html || found_in_erb
            used_controllers << controller
          end
        end
      end

      used_controllers = used_controllers.uniq

      system_controllers = controller_data.select { |name, data| data[:is_system_controller] }.keys
      checkable_controllers = controller_data.keys - system_controllers
      unused_controllers = checkable_controllers - used_controllers

      puts "\n📊 Controller Usage Statistics:"
      puts "   • Total controllers: #{total_controllers}"
      puts "   • System controllers: #{system_controllers.length} (#{system_controllers.join(', ')})" if system_controllers.any?
      puts "   • Used in views: #{used_controllers.length}"
      puts "   • Unused: #{unused_controllers.length}"

      if unused_controllers.any?
        puts "   ⚠️  Unused controllers: #{unused_controllers.join(', ')}"
      end

      expect(controller_data).not_to be_empty
    end
  end

  describe 'Quick Fix Suggestions' do
    it 'generates actionable fix commands' do
      missing_controllers = []

      view_files.each do |view_file|
        content = File.read(view_file)
        doc = Nokogiri::HTML::DocumentFragment.parse(content)

        doc.css('[data-controller], [data-action]').each do |element|
          if controller_attr = element['data-controller']
            controller_attr.split(/\s+/).each do |controller|
              unless controller_data.key?(controller)
                missing_controllers << controller
              end
            end
          end

          if action_attr = element['data-action']
            # Parse action string using existing method
            parsed_actions = parse_action_string(action_attr)
            parsed_actions.each do |action_info|
              controller = action_info[:controller]
              unless controller_data.key?(controller)
                missing_controllers << controller
              end
            end
          end
        end
      end

      missing_controllers = missing_controllers.uniq

      if missing_controllers.any?
        puts "\n🔧 Quick Fix Commands:"
        missing_controllers.each do |controller|
          puts "   rails generate stimulus_controller #{controller.gsub('-', '_')}"
        end
      end

      expect(missing_controllers).to be_kind_of(Array)
    end
  end

  describe 'QuerySelector Validation' do
    it 'validates that querySelector calls target elements within controller scope' do
      selector_errors = []
      selector_scope_errors = []

      controller_data.each do |controller_name, data|
        query_selectors = data[:querySelectors] || []
        next if query_selectors.empty?

        # Find view files that use this controller
        view_files.each do |view_file|
          content = File.read(view_file)
          relative_path = view_file.sub(Rails.root.to_s + '/', '')
          doc = Nokogiri::HTML::DocumentFragment.parse(content)

          # Find all elements with this controller
          controller_elements = doc.css("[data-controller]").select do |element|
            element['data-controller'].split(/\s+/).include?(controller_name)
          end

          next if controller_elements.empty?

          # Check each querySelector call
          query_selectors.each do |qs|
            selector = qs['selector']
            method = qs['method']
            in_method = qs['inMethod']
            line = qs['line']
            is_template = qs['isTemplate']
            skip_validation = qs['skipValidation']

            # Skip template literals for now (they're dynamic)
            if is_template
              next
            end

            # Skip if marked with stimulus-validator: disable-next-line comment
            if skip_validation
              next
            end

            # Track if we found the selector in at least one controller scope
            found_in_scope = false
            found_outside_scope = false

            controller_elements.each do |controller_element|
              # Try to find elements matching the selector within the controller scope
              begin
                matching_elements = controller_element.css(selector)
                if matching_elements.any?
                  found_in_scope = true
                  break
                end
              rescue Nokogiri::CSS::SyntaxError
                # Invalid CSS selector, skip
                next
              end
            end

            # Check if selector exists elsewhere in the document (outside controller scope)
            unless found_in_scope
              begin
                matching_elements = doc.css(selector)
                if matching_elements.any?
                  # Check if these elements are outside all controller scopes
                  matching_elements.each do |element|
                    is_outside = controller_elements.all? do |controller_element|
                      !controller_element.css('*').include?(element) && element != controller_element
                    end
                    if is_outside
                      found_outside_scope = true
                      break
                    end
                  end
                end
              rescue Nokogiri::CSS::SyntaxError
                # Invalid CSS selector, skip
                next
              end
            end

            unless found_in_scope
              controller_file = data[:file].sub(Rails.root.to_s + '/', '')

              if found_outside_scope
                # Selector exists but is out of scope
                selector_scope_errors << {
                  controller: controller_name,
                  selector: selector,
                  method: in_method,
                  line: line,
                  controller_file: controller_file,
                  view_file: relative_path,
                  suggestion: "Selector '#{selector}' exists in #{relative_path} but is outside the '#{controller_name}' controller scope. Move the element(s) inside <div data-controller=\"#{controller_name}\">...</div>."
                }
              else
                # Selector doesn't exist at all
                selector_errors << {
                  controller: controller_name,
                  selector: selector,
                  method: in_method,
                  line: line,
                  controller_file: controller_file,
                  view_file: relative_path,
                  suggestion: "Selector '#{selector}' not found in #{relative_path}. Add an element with this selector within the '#{controller_name}' controller scope."
                }
              end
            end
          end
        end
      end

      total_errors = selector_errors.length + selector_scope_errors.length
      MAX_DISPLAY_ERRORS = 5

      puts "\n🔍 QuerySelector Validation Results:"
      total_selectors = controller_data.values.map { |d| (d[:querySelectors] || []).length }.sum
      puts "   📁 Found: #{total_selectors} querySelector calls across #{controller_data.keys.length} controllers"

      if total_errors == 0
        puts "   ✅ All querySelector calls are valid!"
      else
        puts "\n   ❌ Found #{total_errors} issue(s):"

        displayed_count = 0

        if selector_errors.any?
          display_count = [selector_errors.length, MAX_DISPLAY_ERRORS - displayed_count].min
          puts "\n   🔍 Missing Selectors (#{selector_errors.length}):"
          selector_errors.take(display_count).each do |error|
            puts "     • #{error[:controller]}##{error[:method]}() at #{error[:controller_file]}:#{error[:line]}"
            puts "       Selector '#{error[:selector]}' not found in #{error[:view_file]}"
          end
          displayed_count += display_count

          if selector_errors.length > display_count
            remaining = selector_errors.length - display_count
            puts "       ... and #{remaining} more. Fix these first, then re-run to see remaining errors."
          end
        end

        if selector_scope_errors.any? && displayed_count < MAX_DISPLAY_ERRORS
          display_count = [selector_scope_errors.length, MAX_DISPLAY_ERRORS - displayed_count].min
          puts "\n   🔍 Selector Out of Scope Errors (#{selector_scope_errors.length}):"
          selector_scope_errors.take(display_count).each do |error|
            puts "     • #{error[:controller]}##{error[:method]}() at #{error[:controller_file]}:#{error[:line]}"
            puts "       Selector '#{error[:selector]}' exists but is out of scope in #{error[:view_file]}"
          end
          displayed_count += display_count

          if selector_scope_errors.length > display_count
            remaining = selector_scope_errors.length - display_count
            puts "       ... and #{remaining} more. Fix these first, then re-run to see remaining errors."
          end
        end

        if selector_errors.any? || selector_scope_errors.any?
          puts "\n   💡 If you've confirmed the selector is used dynamically or elsewhere, add '// stimulus-validator: disable-next-line' before the querySelector call."
        end

        error_details = []

        # Only include first MAX_DISPLAY_ERRORS in error details
        all_errors = selector_errors + selector_scope_errors
        all_errors.take(MAX_DISPLAY_ERRORS).each do |error|
          if error.key?(:view_file)
            if selector_errors.include?(error)
              error_details << "Missing selector: #{error[:controller]}##{error[:method]}() uses '#{error[:selector]}' at #{error[:controller_file]}:#{error[:line]} - #{error[:suggestion]}"
            else
              error_details << "Selector out of scope: #{error[:controller]}##{error[:method]}() uses '#{error[:selector]}' at #{error[:controller_file]}:#{error[:line]} - #{error[:suggestion]}"
            end
          end
        end

        if total_errors > MAX_DISPLAY_ERRORS
          error_details << "\n... and #{total_errors - MAX_DISPLAY_ERRORS} more errors. Fix the above first, then re-run to see remaining errors."
        end

        expect(total_errors).to eq(0), "QuerySelector validation failed:\n#{error_details.join("\n")}"
      end
    end
  end

  describe 'Controller Registration Validation' do
    it 'ensures all controllers are imported and registered in index.ts' do
      registration_errors = []
      index_file = Rails.root.join('app/javascript/controllers/index.ts')

      # Skip validation if index.ts doesn't exist
      unless File.exist?(index_file)
        puts "\n⚠️  Skipping controller registration check: index.ts not found"
        next
      end

      index_content = File.read(index_file)

      # Get all controller files, excluding base_* controllers
      controller_files = Dir.glob(controllers_dir.join('*_controller.ts')).reject do |file|
        File.basename(file).start_with?('base_')
      end

      controller_files.each do |file|
        controller_name = File.basename(file, '.ts').gsub('_controller', '')
        class_name = controller_name.split('_').map(&:capitalize).join('') + 'Controller'
        kebab_name = controller_name.gsub('_', '-')

        # Check if imported
        import_pattern = /import\s+#{class_name}\s+from\s+["']\.\/#{controller_name}_controller["']/
        unless index_content.match?(import_pattern)
          registration_errors << {
            controller: controller_name,
            file: file.sub(Rails.root.to_s + '/', ''),
            error_type: 'missing_import',
            suggestion: "Add to index.ts: import #{class_name} from \"./#{controller_name}_controller\""
          }
        end

        # Check if registered
        register_pattern = /application\.register\s*\(\s*["']#{kebab_name}["']\s*,\s*#{class_name}\s*\)/
        unless index_content.match?(register_pattern)
          registration_errors << {
            controller: controller_name,
            file: file.sub(Rails.root.to_s + '/', ''),
            error_type: 'missing_registration',
            suggestion: "Add to index.ts: application.register(\"#{kebab_name}\", #{class_name})"
          }
        end
      end

      if registration_errors.any?
        puts "\n⚠️  Controller Registration Errors (#{registration_errors.length}):"

        missing_imports = registration_errors.select { |e| e[:error_type] == 'missing_import' }
        missing_registrations = registration_errors.select { |e| e[:error_type] == 'missing_registration' }

        if missing_imports.any?
          puts "\n   📦 Missing Imports (#{missing_imports.length}):"
          missing_imports.each do |error|
            puts "     • #{error[:file]}"
            puts "       💡 #{error[:suggestion]}"
          end
        end

        if missing_registrations.any?
          puts "\n   🔌 Missing Registrations (#{missing_registrations.length}):"
          missing_registrations.each do |error|
            puts "     • #{error[:file]}"
            puts "       💡 #{error[:suggestion]}"
          end
        end

        error_details = registration_errors.map { |e| "#{e[:file]} - #{e[:suggestion]}" }
        expect(registration_errors).to be_empty,
          "Controller registration validation failed:\n#{error_details.join("\n")}"
      else
        puts "\n✅ All controllers are properly imported and registered in index.ts!"
      end
    end
  end
end
