import { onBeforeUnmount, watch, type Ref } from 'vue'

/**
 * 弹层焦点管理：打开时把焦点移入面板、Tab/Shift+Tab 在面板内循环、
 * Esc 关闭、关闭后把焦点还给触发元素。
 *
 * 所有 Sheet 和 ConfirmDialog 共用一份实现，避免各页面重复。打开多个弹层时，
 * 只有最后打开的那一个（栈顶）处理键盘事件，因此 ConfirmDialog 覆盖在表单
 * Sheet 上时不会出现两个弹层同时响应 Esc 的情况。
 */

const FOCUSABLE_SELECTOR = [
  'a[href]',
  'button:not([disabled])',
  'input:not([disabled])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  '[tabindex]:not([tabindex="-1"])'
].join(',')

/** 当前打开的弹层面板，后进先出。 */
const dialogStack: HTMLElement[] = []

export interface DialogFocusOptions {
  /** 顶层弹层按下 Esc 时调用。 */
  onClose?: () => void
  /** 打开后优先聚焦的元素；未提供时聚焦面板本身。 */
  initialFocus?: () => HTMLElement | null | undefined
  /** 关闭后要还原焦点的元素；未提供时使用打开前的 document.activeElement。 */
  returnFocus?: () => HTMLElement | null | undefined
}

function isVisible(element: HTMLElement): boolean {
  return element.getClientRects().length > 0
    && element.getAttribute('aria-hidden') !== 'true'
}

export function useDialogFocus(
  panel: Ref<HTMLElement | null>,
  options: DialogFocusOptions = {}
): void {
  let panelNode: HTMLElement | null = null
  let returnFocus: HTMLElement | null = null

  function isTopmost(): boolean {
    return dialogStack[dialogStack.length - 1] === panelNode
  }

  function focusableElements(): HTMLElement[] {
    if (!panelNode) return []
    return Array.from(panelNode.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR))
      .filter(isVisible)
  }

  function focusInitial(): void {
    if (!panelNode) return
    const target = options.initialFocus?.()
    if (target) {
      target.focus()
      return
    }
    // 面板自身 tabindex="-1"，内容没有任何可聚焦元素时也能接住焦点。
    panelNode.focus()
  }

  function onKeydown(event: KeyboardEvent): void {
    if (!panelNode || !isTopmost()) return

    if (event.key === 'Escape') {
      // 只拦截顶层弹层，避免 Esc 同时关闭它和它后面的 Sheet。
      event.preventDefault()
      event.stopPropagation()
      options.onClose?.()
      return
    }

    if (event.key !== 'Tab') return

    const focusable = focusableElements()
    if (focusable.length === 0) {
      // 面板没有可聚焦内容：把 Tab 留在面板上，避免焦点逃到背景页面。
      event.preventDefault()
      panelNode.focus()
      return
    }

    const first = focusable[0]
    const last = focusable[focusable.length - 1]
    const active = document.activeElement instanceof HTMLElement ? document.activeElement : null

    if (event.shiftKey) {
      if (active === first || active === panelNode || !panelNode.contains(active)) {
        event.preventDefault()
        last.focus()
      }
      return
    }

    if (active === last || active === panelNode || !panelNode.contains(active)) {
      event.preventDefault()
      first.focus()
    }
  }

  function attach(node: HTMLElement): void {
    panelNode = node
    // 记录打开前的焦点，关闭时还原到触发按钮/输入框。
    returnFocus = options.returnFocus?.()
      ?? (document.activeElement instanceof HTMLElement ? document.activeElement : null)
    dialogStack.push(node)
    focusInitial()
    document.addEventListener('keydown', onKeydown, true)
  }

  function detach(): void {
    if (!panelNode) return
    document.removeEventListener('keydown', onKeydown, true)
    const index = dialogStack.indexOf(panelNode)
    if (index >= 0) dialogStack.splice(index, 1)
    panelNode = null
    if (returnFocus?.isConnected) returnFocus.focus()
    returnFocus = null
  }

  // 面板可能通过 v-if 在页面打开后才出现（例如教练页的历史弹层），
  // 因此监听 ref 变化而不是只在组件 onMounted 时处理一次。
  watch(
    panel,
    (node) => {
      if (node && node !== panelNode) {
        detach()
        attach(node)
      } else if (!node) {
        detach()
      }
    },
    { flush: 'post' }
  )

  onBeforeUnmount(detach)
}
