import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"
import type { TomInput, TomSettings, RecursivePartial } from "tom-select/dist/types/types"

// Tom Select Stimulus Controller
// Enhances native <select> elements with search, multi-select, and AJAX capabilities
//
// Usage:
//   <%= form.select :category_id, options, {}, {
//     data: { controller: "tom-select" }
//   } %>
//
// With options:
//   <%= form.select :tags, options, {}, {
//     data: {
//       controller: "tom-select",
//       tom_select_max_items_value: 5,
//       tom_select_placeholder_value: "Select tags..."
//     },
//     multiple: true
//   } %>

export default class extends Controller {
  static values = {
    placeholder: String,
    maxItems: Number,
    searchField: { type: Array, default: ["text"] },
    allowEmptyOption: { type: Boolean, default: true },
    create: { type: Boolean, default: false },
    plugins: { type: Array, default: [] }
  }

  declare placeholderValue: string
  declare maxItemsValue: number
  declare searchFieldValue: string[]
  declare allowEmptyOptionValue: boolean
  declare createValue: boolean
  declare pluginsValue: string[]

  declare readonly hasPlaceholderValue: boolean
  declare readonly hasMaxItemsValue: boolean

  private tomSelect: TomSelect | null = null

  connect() {
    const element = this.element as HTMLSelectElement

    // Build configuration
    const config: RecursivePartial<TomSettings> = {
      // Core options
      allowEmptyOption: this.allowEmptyOptionValue,
      searchField: this.searchFieldValue,

      // Styling
      controlInput: null, // Hide the input when single select

      // Placeholder
      ...(this.hasPlaceholderValue && {
        placeholder: this.placeholderValue
      }),

      // Max items (for multi-select)
      ...(this.hasMaxItemsValue && {
        maxItems: this.maxItemsValue
      }),

      // Allow creating new options
      ...(this.createValue && {
        create: true,
        createOnBlur: true
      }),

      // Plugins
      ...(this.pluginsValue.length > 0 && {
        plugins: this.buildPlugins()
      }),

      // Keyboard navigation
      closeAfterSelect: !element.multiple,

      // Performance
      loadThrottle: 300,

      // Rendering
      render: {
        no_results: () => {
          return '<div class="no-results">No results found</div>'
        }
      }
    }

    // Initialize Tom Select
    this.tomSelect = new TomSelect(element, config)
  }

  disconnect() {
    if (this.tomSelect) {
      this.tomSelect.destroy()
      this.tomSelect = null
    }
  }

  // Public API: Clear selection
  clear() {
    if (this.tomSelect) {
      this.tomSelect.clear()
    }
  }

  // Public API: Add option
  addOption(value: string, text: string) {
    if (this.tomSelect) {
      this.tomSelect.addOption({ value, text })
    }
  }

  // Public API: Refresh options
  refresh() {
    if (this.tomSelect) {
      this.tomSelect.refreshOptions(false)
    }
  }

  private buildPlugins(): string[] | Record<string, any> {
    const plugins: Record<string, any> = {}

    this.pluginsValue.forEach(plugin => {
      switch (plugin) {
        case 'remove_button':
          plugins['remove_button'] = { title: 'Remove' }
          break
        case 'clear_button':
          plugins['clear_button'] = { title: 'Clear All' }
          break
        case 'dropdown_header':
          plugins['dropdown_header'] = {}
          break
        default:
          plugins[plugin] = {}
      }
    })

    return plugins
  }
}
