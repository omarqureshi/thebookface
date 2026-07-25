import { Controller } from "@hotwired/stimulus"

// Attaches images to a post. On pick, each file is downscaled in the browser
// (so what lands in S3 is already web-sized — no server-side processing needed
// for the demo), uploaded straight to S3 via a presigned POST, and its key added
// to a hidden field the post form submits. Bytes never touch the Rails app.
export default class extends Controller {
  static targets = ["input", "previews", "field", "submit"]
  static values = { url: String, max: { type: Number, default: 4 } }

  connect() {
    this.media = []
    this.inFlight = 0
  }

  open() { this.inputTarget.click() }

  async pick(event) {
    const files = Array.from(event.target.files || [])
    event.target.value = "" // let the same file be re-picked
    for (const file of files) {
      if (this.media.length >= this.maxValue) break
      if (!file.type.startsWith("image/")) continue
      await this.handle(file)
    }
  }

  async handle(file) {
    this.busy(1)
    const placeholder = this.addPreview()
    try {
      const { blob, type, width, height } = await this.downscale(file)
      const presigned = await this.presign(type)
      await this.upload(presigned, blob)
      this.media.push({ key: presigned.key, content_type: type, width, height })
      this.fieldTarget.value = JSON.stringify(this.media)
      placeholder.style.backgroundImage = `url(${URL.createObjectURL(blob)})`
      placeholder.classList.remove("is-loading")
      placeholder.dataset.key = presigned.key
    } catch (err) {
      placeholder.remove()
      console.error("upload failed", err)
      alert("Sorry — that image couldn't be uploaded.")
    } finally {
      this.busy(-1)
    }
  }

  remove(event) {
    const tile = event.target.closest("[data-key]")
    if (!tile) return
    this.media = this.media.filter((m) => m.key !== tile.dataset.key)
    this.fieldTarget.value = JSON.stringify(this.media)
    tile.remove()
  }

  // --- helpers ---

  // GIFs pass through untouched (keep animation); everything else is drawn onto
  // a canvas at <= 1600px and re-encoded as JPEG.
  downscale(file) {
    if (file.type === "image/gif") return Promise.resolve({ blob: file, type: file.type, width: 0, height: 0 })
    return new Promise((resolve, reject) => {
      const img = new Image()
      img.onload = () => {
        const scale = Math.min(1, 1600 / Math.max(img.width, img.height))
        const w = Math.round(img.width * scale)
        const h = Math.round(img.height * scale)
        const canvas = document.createElement("canvas")
        canvas.width = w; canvas.height = h
        canvas.getContext("2d").drawImage(img, 0, 0, w, h)
        canvas.toBlob((blob) => blob ? resolve({ blob, type: "image/jpeg", width: w, height: h }) : reject(new Error("encode failed")), "image/jpeg", 0.85)
      }
      img.onerror = reject
      img.src = URL.createObjectURL(file)
    })
  }

  async presign(contentType) {
    const res = await fetch(this.urlValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrf },
      body: JSON.stringify({ content_type: contentType })
    })
    if (!res.ok) throw new Error(`presign ${res.status}`)
    return res.json()
  }

  async upload(presigned, blob) {
    const form = new FormData()
    Object.entries(presigned.fields).forEach(([k, v]) => form.append(k, v))
    form.append("file", blob, "upload") // must be last
    const res = await fetch(presigned.url, { method: "POST", body: form })
    if (res.status !== 201 && res.status !== 204) throw new Error(`upload ${res.status}`)
  }

  addPreview() {
    const tile = document.createElement("div")
    tile.className = "upload-tile is-loading"
    const del = document.createElement("button")
    del.type = "button"; del.className = "upload-tile__remove"; del.textContent = "×"
    del.dataset.action = "uploader#remove"
    tile.appendChild(del)
    this.previewsTarget.appendChild(tile)
    return tile
  }

  busy(delta) {
    this.inFlight += delta
    if (this.hasSubmitTarget) this.submitTarget.disabled = this.inFlight > 0
  }

  get csrf() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }
}
