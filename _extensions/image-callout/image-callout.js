// image-callout runtime (revealjs only).
// 1. hand .ic-stretch containers over to reveal's .r-stretch layout. The class
//    cannot be in the static HTML because Quarto's revealjs postprocessor
//    would move the image out of a .r-stretch div.
// 2. cover mode: when a theme takes the image out of flow (position:absolute,
//    e.g. a full-bleed photo slide), the stage collapses to 0x0. Then the
//    annotations are moved into an overlay box kept on top of the image and
//    fitted like the image's object-fit (cover/contain/fill).
(function () {
  function stretch() {
    var els = document.querySelectorAll(".reveal .image-callout.ic-stretch");
    if (!els.length) return;
    els.forEach(function (el) { el.classList.add("r-stretch"); });
    if (window.Reveal && typeof Reveal.layout === "function") {
      if (Reveal.isReady && Reveal.isReady()) {
        Reveal.layout();
      } else if (typeof Reveal.on === "function") {
        Reveal.on("ready", function () { Reveal.layout(); });
      }
    }
  }

  // shortcut: follows the image size only (ResizeObserver), not a pure
  // position change; upgrade if a theme moves images without resizing them.
  function place(img, box, stage) {
    if (!img.offsetWidth) return; // slide not displayed yet
    if (!stage.style.getPropertyValue("--ic-ratio") && img.naturalWidth) {
      stage.style.setProperty("--ic-ratio", img.naturalWidth + " / " + img.naturalHeight);
    }
    // img and box share the containing block (stage and container are static)
    box.style.left = img.offsetLeft + "px";
    box.style.top = img.offsetTop + "px";
    box.style.width = img.offsetWidth + "px";
    box.style.height = img.offsetHeight + "px";
    var fit = getComputedStyle(img).objectFit;
    box.className = "ic-box ic-fit-" +
      (stage.style.getPropertyValue("--ic-ratio") && (fit === "cover" || fit === "contain") ? fit : "fill");
  }

  function cover() {
    document.querySelectorAll(".image-callout").forEach(function (el) {
      var stage = el.querySelector(":scope > .ic-stage, :scope > .ic-frame > .ic-stage");
      var img = stage && stage.querySelector(":scope > p > img.ic-image, :scope > img.ic-image");
      if (!img || getComputedStyle(img).position !== "absolute") return;
      el.classList.add("ic-cover");
      var box = document.createElement("div");
      var inner = document.createElement("div");
      inner.className = "ic-fit";
      stage.querySelectorAll(":scope > .ic-item").forEach(function (it) { inner.appendChild(it); });
      box.appendChild(inner);
      stage.appendChild(box);
      var update = function () { place(img, box, stage); };
      img.addEventListener("load", update);
      if (window.ResizeObserver) new ResizeObserver(update).observe(img);
      update();
    });
  }

  function apply() {
    cover();
    stretch();
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", apply);
  } else {
    apply();
  }
})();
