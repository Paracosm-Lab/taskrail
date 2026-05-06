import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  switch(event) {
    const selected = event.currentTarget.dataset.tab

    this.tabTargets.forEach(tab => {
      const active = tab.dataset.tab === selected
      tab.classList.toggle("border-blue", active)
      tab.classList.toggle("text-blue", active)
      tab.classList.toggle("border-transparent", !active)
      tab.classList.toggle("text-overlay0", !active)
    })

    this.panelTargets.forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.tab !== selected)
    })
  }
}
