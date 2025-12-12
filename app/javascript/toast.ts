function createToastContainer(): HTMLElement {
  let container = document.getElementById('toast-container')
  if (!container) {
    container = document.createElement('div')
    container.id = 'toast-container'
    container.className = 'fixed top-4 right-4 z-50 flex flex-col gap-2 pointer-events-none'
    document.body.appendChild(container)
  }
  return container
}

window.showToast = function(message: string, type: 'success' | 'error' | 'info' | 'warning' = 'info'): void {
  const container = createToastContainer()

  const alertType = type === 'error' ? 'danger' : type

  const toast = document.createElement('div')
  toast.className = `alert-${alertType} pointer-events-auto max-w-md shadow-lg transform transition-all duration-300 ease-out translate-x-0 opacity-100 !py-2 !px-3`

  toast.innerHTML = `
    <div class="flex items-center gap-3">
      <span class="flex-1">${message}</span>
      <button class="ml-2 p-1 rounded hover:bg-black/10 transition-colors" aria-label="Close">
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
        </svg>
      </button>
    </div>
  `

  const closeButton = toast.querySelector('button')
  closeButton?.addEventListener('click', () => {
    removeToast(toast)
  })

  toast.style.transform = 'translateX(400px)'
  toast.style.opacity = '0'
  container.appendChild(toast)

  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      toast.style.transform = 'translateX(0)'
      toast.style.opacity = '1'
    })
  })

  setTimeout(() => {
    removeToast(toast)
  }, 3000)
}

function removeToast(toast: HTMLElement): void {
  toast.style.transform = 'translateX(400px)'
  toast.style.opacity = '0'

  setTimeout(() => {
    toast.remove()

    const container = document.getElementById('toast-container')
    if (container && container.children.length === 0) {
      container.remove()
    }
  }, 300)
}
