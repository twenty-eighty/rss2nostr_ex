import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const Hooks = {
  SourceAvatars: {
    mounted() {
      this.load()
    },
    updated() {
      this.load()
    },
    load() {
      const imgs = Array.prototype.slice.call(
        this.el.querySelectorAll("img.source-avatar[data-pubkey]")
      )
      if (!imgs.length) return

      const relays = (this.el.getAttribute("data-relays") || "")
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean)
      const byAuthor = {}

      imgs.forEach((img) => {
        const pubkey = img.getAttribute("data-pubkey")
        if (!pubkey) return
        ;(byAuthor[pubkey] = byAuthor[pubkey] || []).push(img)
        try {
          const cached = sessionStorage.getItem("rss2nostr-avatar-" + pubkey)
          if (cached) img.src = cached
        } catch (_e) {}
      })

      const authors = Object.keys(byAuthor)
      if (!authors.length || !relays.length) return

      relays.forEach((url) => {
        let ws
        try {
          ws = new WebSocket(url)
        } catch (_e) {
          return
        }
        const sub = "src-avatars"
        ws.onopen = () => {
          ws.send(JSON.stringify(["REQ", sub, {kinds: [0], authors}]))
        }
        ws.onmessage = (event) => {
          let msg
          try {
            msg = JSON.parse(event.data)
          } catch (_e) {
            return
          }
          if (msg[0] === "EVENT" && msg[2] && msg[2].kind === 0) {
            applyProfile(msg[2], byAuthor)
          }
          if (msg[0] === "EOSE") {
            try {
              ws.send(JSON.stringify(["CLOSE", sub]))
            } catch (_e) {}
            try {
              ws.close()
            } catch (_e) {}
          }
        }
      })
    }
  }
}

function applyProfile(event, byAuthor) {
  let content
  try {
    content = JSON.parse(event.content || "{}")
  } catch (_e) {
    return
  }
  const picture = content.picture
  if (!picture) return
  const created = event.created_at || 0
  ;(byAuthor[event.pubkey] || []).forEach((img) => {
    const prev = Number(img.getAttribute("data-created-at") || 0)
    if (created < prev) return
    img.setAttribute("data-created-at", String(created))
    img.src = picture
    try {
      sessionStorage.setItem("rss2nostr-avatar-" + event.pubkey, picture)
    } catch (_e) {}
  })
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

liveSocket.connect()
window.liveSocket = liveSocket
