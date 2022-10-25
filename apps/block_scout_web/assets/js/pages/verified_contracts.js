import $ from 'jquery'
import omit from 'lodash.omit'
import { loadPage, createAsyncLoadStore } from '../lib/async_listing_load'
import { connectElements } from '../lib/redux_helpers.js'

export const initialState = {
  isSearch: false
}

const elements = {
  '[data-search-field]': {
    render ($el, state) {
      return $el
    }
  },
  '[data-search-button]': {
    render ($el, state) {
      return $el
    }
  },
  '[data-cancel-search-button]': {
    render ($el, state) {
      if (!state.isSearch) {
        return $el.hide()
      }

      return $el.show()
    }
  },
  '[data-search]': {
    render ($el, state) {
      if (state.emptyResponse && !state.isSearch) {
        return $el.hide()
      }

      return $el.show()
    }
  }
}

export function reducer (state, action) {
  switch (action.type) {
    case 'PAGE_LOAD':
    case 'ELEMENTS_LOAD': {
      return Object.assign({}, state, omit(action, 'type'))
    }
    case 'START_SEARCH': {
      return Object.assign({}, state, { pagesStack: [], isSearch: true })
    }
    default:
      return state
  }
}

if ($('[data-page="verified-contracts-list"]').length) {
  let timer
  const waitTime = 500

  const store = createAsyncLoadStore(reducer, initialState, 'dataset.identifierHash')

  connectElements({ store, elements })

  const $element = $('[data-async-listing]')

  const searchFunc = (_event) => {
    store.dispatch({ type: 'START_SEARCH' })
    const searchInput = $('[data-search-field]').val()
    const path = window.location.pathname + '?search=' + searchInput
    loadPage(store, path)
  }

  store.dispatch({
    type: 'PAGE_LOAD'
  })

  $element.on('click', '[data-search-button]', searchFunc)

  $element.on('click', '[data-cancel-search-button]', (_event) => {
    $('[data-search-field]').val('')
    loadPage(store, window.location.pathname)
  })

  $element.on('input keyup', '[data-search-field]', (event) => {
    if (event.type === 'input') {
      clearTimeout(timer)
      timer = setTimeout(() => {
        searchFunc(event)
      }, waitTime)
    }
    if (event.type === 'keyup' && event.keyCode === 13) {
      clearTimeout(timer)
      searchFunc(event)
    }
  })
}
