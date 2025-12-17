import { Controller } from "@hotwired/stimulus"
import { showToast } from "../toast"

// stimulus-validator: system-controller
export default class extends Controller {
  static values = {
    message: String,
    type: String,
    position: { type: String, default: 'top-center' },
    duration: { type: Number, default: 3000 }
  }

  declare readonly messageValue: string
  declare readonly typeValue: string
  declare readonly positionValue: 'top-right' | 'top-center' | 'top-left'
  declare readonly durationValue: number

  connect(): void {
    // Show toast when controller connects
    if (this.messageValue) {
      showToast(
        this.messageValue,
        this.typeValue as any,
        this.positionValue,
        this.durationValue
      )
    }
  }
}
