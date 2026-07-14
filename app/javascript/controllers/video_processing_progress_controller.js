import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bar", "value", "spinner", "title", "message"]
  static values = { statusUrl: String, failureMessage: String }

  connect() {
    this.requestInProgress = false
    this.stopped = false
    this.checkStatus()
    this.pollingInterval = window.setInterval(() => this.checkStatus(), 3000)
  }

  disconnect() {
    this.stopPolling()
  }

  async checkStatus() {
    if (this.requestInProgress || this.stopped) return
    this.requestInProgress = true

    try {
      const response = await fetch(this.statusUrlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin",
      })
      if (!response.ok) throw new Error(`Status request failed: ${response.status}`)

      const data = await response.json()
      this.updateProgress(data.processing_progress)

      if (data.concat_status === "completed") {
        this.stopPolling()
        window.location.reload()
      } else if (data.concat_status === "failed") {
        this.showFailure()
      }
    } catch (error) {
      console.error("Unable to check video processing status", error)
    } finally {
      this.requestInProgress = false
    }
  }

  updateProgress(value) {
    const progress = Math.max(0, Math.min(100, Number(value) || 0))
    this.barTarget.style.width = `${progress}%`
    this.barTarget.setAttribute("aria-valuenow", progress)
    this.valueTarget.textContent = `${progress}%`
  }

  showFailure() {
    this.stopPolling()
    this.element.classList.add("video-processing-state--failed")
    if (this.hasSpinnerTarget) this.spinnerTarget.remove()
    this.titleTarget.textContent = this.failureMessageValue
    this.messageTarget.textContent = ""
  }

  stopPolling() {
    this.stopped = true
    if (this.pollingInterval) window.clearInterval(this.pollingInterval)
  }
}
