import { Controller } from "@hotwired/stimulus"

// Uploads a single profile avatar. On pick, the image is downscaled to a small
// square-ish JPEG in the browser, pushed straight to S3 via a presigned POST
// (the same /uploads endpoint as post images), and its key dropped into the
// hidden field the profile form submits. Bytes never touch the Rails app.
export default class extends Controller {
  static targets = ["input", "preview", "field", "submit"]
  static values = { url: String }

  open() { this.inputTarget.click() }

  async pick(event) {
    const file = (event.target.files || [])[0]
    event.target.value = "" // let the same file be re-picked
    if (!file || !file.type.startsWith("image/")) return
    this.busy(true)
    try {
      const { blob, type } = await this.downscale(file)
      const presigned = await this.presign(type)
      await this.upload(presigned, blob)
      this.fieldTarget.value = presigned.key
      this.previewTarget.textContent = ""
      this.previewTarget.classList.add("avatar--photo")
      this.previewTarget.style.backgroundImage = `url(${URL.createObjectURL(blob)})`
    } catch (err) {
      console.error("avatar upload failed", err)
      alert("Sorry — that image couldn't be uploaded.")
    } finally {
      this.busy(false)
    }
  }

  // --- helpers ---

  // Draw onto a <= 256px canvas and re-encode as JPEG (GIFs pass through).
  downscale(file) {
    if (file.type === "image/gif") return Promise.resolve({ blob: file, type: file.type })
    return new Promise((resolve, reject) => {
      const img = new Image()
      img.onload = () => {
        const scale = Math.min(1, 256 / Math.max(img.width, img.height))
        const w = Math.round(img.width * scale)
        const h = Math.round(img.height * scale)
        const canvas = document.createElement("canvas")
        canvas.width = w; canvas.height = h
        canvas.getContext("2d").drawImage(img, 0, 0, w, h)
        canvas.toBlob((blob) => blob ? resolve({ blob, type: "image/jpeg" }) : reject(new Error("encode failed")), "image/jpeg", 0.85)
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
    form.append("file", blob, "avatar") // must be last
    const res = await fetch(presigned.url, { method: "POST", body: form })
    if (res.status !== 201 && res.status !== 204) throw new Error(`upload ${res.status}`)
  }

  busy(on) {
    if (this.hasSubmitTarget) this.submitTarget.disabled = on
  }

  get csrf() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }
}
