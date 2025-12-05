require 'parser/current'

# ERB AST Parser for Stimulus validation
class ErbAstParser
  def initialize(content)
    @content = content
    @erb_blocks = extract_erb_blocks
  end

  # Extract all ERB blocks from content
  def extract_erb_blocks
    blocks = []

    # Extract <%= %> blocks (output)
    @content.scan(/<%=\s*(.*?)\s*%>/m) do |match|
      blocks << {
        type: :output,
        code: match[0].strip,
        full_match: $&,
        position: $~.offset(0)
      }
    end

    # Extract <% %> blocks (execution)
    @content.scan(/<%\s*(.*?)\s*%>/m) do |match|
      next if match[0].strip.start_with?('=') # Skip <%= blocks already captured
      blocks << {
        type: :execution,
        code: match[0].strip,
        full_match: $&,
        position: $~.offset(0)
      }
    end

    blocks = blocks.sort_by { |block| block[:position][0] }

    # Merge blocks that form complete Ruby structures
    merge_block_pairs(blocks)
  end

  # Merge ERB blocks that should be parsed together (e.g., form_with...do and end)
  def merge_block_pairs(blocks)
    merged = []
    skip_indices = Set.new

    blocks.each_with_index do |block, i|
      next if skip_indices.include?(i)

      code = block[:code]

      # Check if this block opens a Ruby block structure (do, do |...|, {, etc.)
      # and doesn't close it
      opens_block = code.match(/\b(do\s*(\|[^|]*\|)?)/) ||
                    code.match(/\{\s*(\|[^|]*\|)?/)

      # Check if the block has an unmatched 'do' by looking for standalone 'end' keyword
      has_unmatched_do = opens_block && !has_end_keyword?(code)

      if has_unmatched_do
        # Look for the matching end/} block using nesting level counting
        merged_code = code.dup
        j = i + 1
        nesting_level = 1  # Start with 1 for the initial unmatched 'do'

        # Find all blocks until nesting level reaches 0
        while j < blocks.length && nesting_level > 0
          next_block = blocks[j]
          next_code = next_block[:code]

          # Remove string literals to avoid counting 'do'/'end' inside strings
          code_without_strings = next_code.gsub(/'[^']*'|"[^"]*"/, '')

          # Count 'do' keywords (opens new nesting level)
          nesting_level += code_without_strings.scan(/\bdo\b/).length

          # Count 'end' keywords (closes nesting level)
          nesting_level -= code_without_strings.scan(/\bend\b/).length

          # Add a newline between merged blocks for proper Ruby syntax
          merged_code += "\n" + next_code
          skip_indices.add(j)

          j += 1
        end

        # Create merged block
        merged << {
          type: block[:type],
          code: merged_code,
          full_match: block[:full_match],
          position: block[:position],
          merged: true
        }
      else
        # Keep block as-is
        merged << block
      end
    end

    merged
  end

  # Find Stimulus targets in ERB blocks
  def find_stimulus_targets(controller_name, target_name)
    results = []

    @erb_blocks.each do |block|
      # Skip blocks that don't contain target-related keywords
      next unless should_parse_for_targets?(block[:code], controller_name, target_name)

      # Parse the code with smart preprocessing - fail fast on errors
      processed_code = preprocess_erb_code(block[:code])
      ast = Parser::CurrentRuby.parse(processed_code)
      target_matches = find_targets_in_ast(ast, controller_name, target_name)

      target_matches.each do |match|
        results << {
          block: block,
          match: match,
          line_number: calculate_line_number(block[:position][0])
        }
      end
    end

    results
  end

  # Find Stimulus actions in ERB blocks
  def find_stimulus_actions(controller_name = nil)
    results = []

    @erb_blocks.each do |block|
      # Skip blocks that don't contain action-related keywords
      next unless should_parse_for_actions?(block[:code])

      # Parse the code with smart preprocessing - fail fast on errors
      processed_code = preprocess_erb_code(block[:code])
      ast = Parser::CurrentRuby.parse(processed_code)
      action_matches = find_actions_in_ast(ast, controller_name)

      action_matches.each do |match|
        results << {
          block: block,
          match: match,
          line_number: calculate_line_number(block[:position][0])
        }
      end
    end

    results
  end

  # Find Stimulus values in ERB blocks
  def find_stimulus_values(controller_name, value_name)
    results = []

    @erb_blocks.each do |block|
      # Skip blocks that don't contain value-related keywords
      next unless should_parse_for_values?(block[:code], controller_name, value_name)

      # Parse the code with smart preprocessing - fail fast on errors
      processed_code = preprocess_erb_code(block[:code])
      ast = Parser::CurrentRuby.parse(processed_code)
      value_matches = find_values_in_ast(ast, controller_name, value_name)

      value_matches.each do |match|
        results << {
          block: block,
          match: match,
          line_number: calculate_line_number(block[:position][0])
        }
      end
    end

    results
  end

  private

  # Check if code has an unmatched 'end' keyword
  # Need to exclude 'end' inside strings (both single and double quoted)
  def has_end_keyword?(code)
    # Remove string literals to avoid matching 'end' inside strings
    # This handles both single and double quoted strings
    code_without_strings = code.gsub(/'[^']*'|"[^"]*"/, '')
    code_without_strings.match?(/\bend\b/)
  end

  # Check if ERB block should be parsed for targets
  def should_parse_for_targets?(code, controller_name, target_name)
    # Must contain 'data' and either 'target' or the specific target name
    return false unless code.include?('data')
    return true if code.include?('target') || code.include?(target_name)
    return true if code.include?(controller_name)
    false
  end

  # Check if ERB block should be parsed for actions
  def should_parse_for_actions?(code)
    # Must contain 'data' and 'action'
    code.include?('data') && code.include?('action')
  end

  # Check if ERB block should be parsed for values
  def should_parse_for_values?(code, controller_name, value_name)
    # Must contain 'data' and either 'value' or the specific value name
    return false unless code.include?('data')
    return true if code.include?('value') || code.include?(value_name)
    return true if code.include?(controller_name)
    false
  end

  # Preprocess ERB code to make it more parseable
  def preprocess_erb_code(code)
    # Skip blocks that don't contain Stimulus-related keywords
    stimulus_keywords = ['data', 'controller', 'target', 'action', 'value']
    return code unless stimulus_keywords.any? { |keyword| code.include?(keyword) }

    # Skip preprocessing for simple expressions that are likely to parse correctly
    return code if code.strip.match?(/^\w+\s*\(.*\)$/) || code.strip.match?(/^[\w\.\[\]]+$/)

    # Handle common ERB patterns that cause parsing issues
    processed = code.dup

    # Skip blocks that are clearly control structures (if, unless, case, etc.)
    return code if processed.strip.match?(/^(if|unless|case|when|else|elsif|end|do|while|for|begin|rescue|ensure)\b/)

    # Skip blocks that look like method definitions or class definitions
    return code if processed.strip.match?(/^(def|class|module)\b/)

    # Skip blocks that are just variable assignments or simple expressions
    return code if processed.strip.match?(/^@?\w+\s*[=\[]/) || processed.strip.match?(/^[\w\.\[\]"']+$/)

    # For method calls with blocks, try to make them parseable
    unless has_end_keyword?(processed)
      if processed.include?(' do |')
        processed += "\nend"
      elsif processed.include?(' do') && !processed.include?('|')
        processed += "\nend"
      end
    end

    # Handle incomplete hash literals
    if processed.count('{') > processed.count('}')
      processed += ' }' * (processed.count('{') - processed.count('}'))
    end

    # Handle incomplete array literals
    if processed.count('[') > processed.count(']')
      processed += ' ]' * (processed.count('[') - processed.count(']'))
    end

    # Handle incomplete parentheses
    if processed.count('(') > processed.count(')')
      processed += ' )' * (processed.count('(') - processed.count(')'))
    end

    processed
  end

  def find_targets_in_ast(node, controller_name, target_name)
    return [] unless node

    matches = []

    case node.type
    when :hash
      matches.concat(find_targets_in_hash(node, controller_name, target_name))
    when :send
      matches.concat(find_targets_in_method_call(node, controller_name, target_name))
    end

    # Recursively search child nodes
    if node.respond_to?(:children)
      node.children.each do |child|
        next unless child.is_a?(Parser::AST::Node)
        matches.concat(find_targets_in_ast(child, controller_name, target_name))
      end
    end

    matches
  end

  def find_targets_in_hash(hash_node, controller_name, target_name)
    matches = []

    # Process hash pairs - in AST, each child is a :pair node
    hash_node.children.each do |pair_node|
      next unless pair_node.type == :pair

      key_node = pair_node.children[0]
      value_node = pair_node.children[1]

      next unless key_node && value_node

      # Handle string keys: "controller-target" => "target"
      if key_node.type == :str && value_node.type == :str
        key_str = key_node.children[0]
        value_str = value_node.children[0]

        if key_str == "#{controller_name}-target" && value_str == target_name
          matches << {
            type: :hash_string_key,
            controller: controller_name,
            target: target_name,
            key_node: key_node,
            value_node: value_node
          }
        end
      end

      # Handle symbol keys: controller_target: "target" or "controller-target": "target"
      if key_node.type == :sym && value_node.type == :str
        key_sym = key_node.children[0]
        value_str = value_node.children[0]

        # Support both formats: underscore and hyphen
        expected_key_underscore = "#{controller_name.gsub('-', '_')}_target"
        expected_key_hyphen = "#{controller_name}-target"

        if (key_sym.to_s == expected_key_underscore || key_sym.to_s == expected_key_hyphen) && value_str == target_name
          matches << {
            type: :hash_symbol_key,
            controller: controller_name,
            target: target_name,
            key_node: key_node,
            value_node: value_node
          }
        end
      end
    end

    matches
  end

  def find_targets_in_method_call(send_node, controller_name, target_name)
    matches = []

    # Look for method calls that might contain data attributes
    # This handles cases like: data: { ... }
    if send_node.children.length >= 2
      method_name = send_node.children[1]

      # Check if this is a method call with hash arguments
      send_node.children[2..-1].each do |arg|
        next unless arg.is_a?(Parser::AST::Node) && arg.type == :hash
        matches.concat(find_targets_in_hash(arg, controller_name, target_name))
      end
    end

    matches
  end

  def find_actions_in_ast(node, controller_name)
    return [] unless node

    matches = []

    case node.type
    when :hash
      matches.concat(find_actions_in_hash(node, controller_name))
    when :send
      matches.concat(find_actions_in_method_call(node, controller_name))
    end

    # Recursively search child nodes
    if node.respond_to?(:children)
      node.children.each do |child|
        next unless child.is_a?(Parser::AST::Node)
        matches.concat(find_actions_in_ast(child, controller_name))
      end
    end

    matches
  end

  def find_actions_in_hash(hash_node, controller_name)
    matches = []

    hash_node.children.each do |pair_node|
      next unless pair_node.type == :pair

      key_node = pair_node.children[0]
      value_node = pair_node.children[1]

      next unless key_node && value_node

      # Look for action keys
      if (key_node.type == :str && key_node.children[0] == "action") ||
         (key_node.type == :sym && key_node.children[0] == :action)

        if value_node.type == :str
          action_string = value_node.children[0]
          parsed_actions = parse_action_string(action_string)

          parsed_actions.each do |action|
            if controller_name.nil? || action[:controller] == controller_name
              matches << {
                type: :hash_action,
                action_string: action_string,
                parsed_action: action,
                key_node: key_node,
                value_node: value_node
              }
            end
          end
        end
      end
    end

    matches
  end

  def find_actions_in_method_call(send_node, controller_name)
    matches = []

    if send_node.children.length >= 2
      send_node.children[2..-1].each do |arg|
        next unless arg.is_a?(Parser::AST::Node) && arg.type == :hash
        matches.concat(find_actions_in_hash(arg, controller_name))
      end
    end

    matches
  end

  def find_values_in_ast(node, controller_name, value_name)
    return [] unless node

    matches = []

    case node.type
    when :hash
      matches.concat(find_values_in_hash(node, controller_name, value_name))
    when :send
      matches.concat(find_values_in_method_call(node, controller_name, value_name))
    end

    # Recursively search child nodes
    if node.respond_to?(:children)
      node.children.each do |child|
        next unless child.is_a?(Parser::AST::Node)
        matches.concat(find_values_in_ast(child, controller_name, value_name))
      end
    end

    matches
  end

  def find_values_in_hash(hash_node, controller_name, value_name)
    matches = []

    hash_node.children.each do |pair_node|
      next unless pair_node.type == :pair

      key_node = pair_node.children[0]
      value_node = pair_node.children[1]

      next unless key_node && value_node

      # Handle string keys: "controller-value-name-value" => "..."
      if key_node.type == :str
        key_str = key_node.children[0]
        kebab_value_name = value_name.gsub(/([a-z])([A-Z])/, '\1-\2').downcase
        expected_key = "#{controller_name}-#{kebab_value_name}-value"

        if key_str == expected_key
          matches << {
            type: :hash_string_key,
            controller: controller_name,
            value: value_name,
            key_node: key_node,
            value_node: value_node
          }
        end
      end

      # Handle symbol keys: controller_value_name_value: "..." or "controller-value-name-value": "..."
      if key_node.type == :sym
        key_sym = key_node.children[0]
        kebab_value_name = value_name.gsub(/([a-z])([A-Z])/, '\1-\2').downcase

        # Support both formats: underscore and hyphen
        expected_key_underscore = "#{controller_name.gsub('-', '_')}_#{value_name.gsub(/([a-z])([A-Z])/, '\1_\2').downcase}_value"
        expected_key_hyphen = "#{controller_name}-#{kebab_value_name}-value"

        if (key_sym.to_s == expected_key_underscore || key_sym.to_s == expected_key_hyphen)
          matches << {
            type: :hash_symbol_key,
            controller: controller_name,
            value: value_name,
            key_node: key_node,
            value_node: value_node
          }
        end
      end
    end

    matches
  end

  def find_values_in_method_call(send_node, controller_name, value_name)
    matches = []

    if send_node.children.length >= 2
      send_node.children[2..-1].each do |arg|
        next unless arg.is_a?(Parser::AST::Node) && arg.type == :hash
        matches.concat(find_values_in_hash(arg, controller_name, value_name))
      end
    end

    matches
  end

  def parse_action_string(action_string)
    return [] unless action_string

    actions = []
    action_parts = action_string.scan(/\S+/)

    action_parts.each do |action|
      if match = action.match(/^(?:(\w+(?:\.\w+)*)->)?(\w+(?:-\w+)*)#(\w+)(?:@\w+)?$/)
        event, controller_name, method_name = match[1], match[2], match[3]
        actions << {
          action: action,
          event: event,
          controller: controller_name,
          method: method_name
        }
      end
    end

    actions
  end

  def calculate_line_number(position)
    @content[0...position].count("\n") + 1
  end

  # Check if AST contains controller definition
  def contains_controller_in_ast?(node, controller_name)
    return false unless node

    case node.type
    when :hash
      node.children.each do |pair_node|
        next unless pair_node.type == :pair

        key_node = pair_node.children[0]
        value_node = pair_node.children[1]

        # Look for controller key with matching value
        if (key_node.type == :str && key_node.children[0] == "controller") ||
           (key_node.type == :sym && key_node.children[0] == :controller)

          if value_node.type == :str && value_node.children[0] == controller_name
            return true
          end
        end
      end
    when :send
      # Check method call arguments
      node.children[2..-1].each do |arg|
        next unless arg.is_a?(Parser::AST::Node)
        return true if contains_controller_in_ast?(arg, controller_name)
      end
    end

    # Recursively search child nodes
    if node.respond_to?(:children)
      node.children.each do |child|
        next unless child.is_a?(Parser::AST::Node)
        return true if contains_controller_in_ast?(child, controller_name)
      end
    end

    false
  end
end
