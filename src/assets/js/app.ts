import "vite/modulepreload-polyfill";
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import type {Hooks} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/network_defense"
import topbar from "topbar"
import {getHooks} from "live_svelte"
import Components from "virtual:live-svelte-components"

const csrfToken = (document.querySelector("meta[name='csrf-token']") as HTMLMetaElement).getAttribute("content")!
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...(colocatedHooks as Hooks), ...getHooks(Components)} as Hooks,
})

topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())

liveSocket.connect()

declare global {
  interface Window {
    liveSocket: LiveSocket
    liveReloader?: { enableServerLogs(): void; disableServerLogs(): void; openEditorAtCaller(el: Element): void; openEditorAtDef(el: Element): void }
  }
}

window.liveSocket = liveSocket

if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ((e: CustomEvent<{
    enableServerLogs(): void
    disableServerLogs(): void
    openEditorAtCaller(el: Element): void
    openEditorAtDef(el: Element): void
  }>) => {
    const reloader = e.detail
    reloader.enableServerLogs()

    let keyDown: string | null = null
    window.addEventListener("keydown", (e: KeyboardEvent) => keyDown = e.key)
    window.addEventListener("keyup", () => keyDown = null)
    window.addEventListener("click", (e: MouseEvent) => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target as Element)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target as Element)
      }
    }, true)

    window.liveReloader = reloader
  }) as EventListener)
}
