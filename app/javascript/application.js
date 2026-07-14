import '@hotwired/turbo-rails'
import 'controllers'

import Swiper from 'swiper'

const swiper = new Swiper('.swiper', {
  navigation: {
    nextEl: '.swiper-button-next',
    prevEl: '.swiper-button-prev',
  },
  pagination: {
    el: '.swiper-pagination',
    clickable: true,
  },
  scrollbar: {
    el: '.swiper-scrollbar',
    hide: true,
  },
})

const navigationButtonSelector = [
  '.black-link',
  '.transparent-link',
  '.transparent-link-smaller',
  '.cta',
  '.cta-transparent',
  '.cta-button',
].join(', ')
const navigationLinkSelector = navigationButtonSelector
  .split(', ')
  .map((selector) => `a${selector}`)
  .join(', ')

function disableNavigationButton(button) {
  if (!button || button.matches(':disabled, [aria-disabled="true"]')) return

  button.dataset.disabledAfterClick = 'true'
  button.classList.add('is-click-disabled')
  button.setAttribute('aria-busy', 'true')

  if (button.matches('button, input')) {
    button.disabled = true
  } else {
    button.setAttribute('aria-disabled', 'true')
  }
}

// Disable form buttons after the submit event so their name/value remains in
// the submitted request while repeated clicks are still blocked.
document.addEventListener('submit', (event) => {
  const form = event.target
  const submitter = event.submitter || (document.activeElement?.form === form ? document.activeElement : null)

  if (!(form instanceof HTMLFormElement) || !submitter?.matches(navigationButtonSelector)) return

  if (form.dataset.submitting === 'true') {
    event.preventDefault()
    return
  }

  form.dataset.submitting = 'true'
  window.setTimeout(() => disableNavigationButton(submitter), 0)
})

// Links do not emit a submit event, so lock them directly after a normal click.
document.addEventListener('click', (event) => {
  const link = event.target.closest(navigationLinkSelector)
  if (!link || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
  if (link.matches('[aria-disabled="true"]')) {
    event.preventDefault()
    return
  }

  disableNavigationButton(link)
})

// Turbo may cache the current page before navigating away. Restore only the
// controls disabled by this behavior so browser Back remains usable.
document.addEventListener('turbo:before-cache', () => {
  document.querySelectorAll('[data-disabled-after-click="true"]').forEach((button) => {
    button.disabled = false
    button.classList.remove('is-click-disabled')
    button.removeAttribute('aria-disabled')
    button.removeAttribute('aria-busy')
    delete button.dataset.disabledAfterClick
  })

  document.querySelectorAll('form[data-submitting="true"]').forEach((form) => {
    delete form.dataset.submitting
  })
})
