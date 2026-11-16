// image-callout: hand .ic-stretch containers over to reveal's .r-stretch
// layout. The class cannot be in the static HTML because Quarto's revealjs
// postprocessor would move the image out of a .r-stretch div.
(function () {
  function apply() {
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
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", apply);
  } else {
    apply();
  }
})();
