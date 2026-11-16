--[[
image-callout.lua -- overlay callouts (ellipse + S-shaped leader + text box)
on top of an image, for Quarto HTML-based formats (revealjs, html).

Markdown:

  :::: {.image-callout}
  ![](figure.png)

  ::: {.annotation x=0.5 y=0.2 tx=0.7 ty=0.3}
  Callout text
  :::
  ::::

All coordinates are fractions (0-1) of the image width/height. A value written
as a percentage ("50%") is accepted too.
]]

local CONTAINER_CLASS = "image-callout"
local ITEM_CLASS = "annotation"

-- Attributes consumed by the filter (everything else is passed through,
-- e.g. fragment-index -> data-fragment-index).
local ITEM_KEYS = {
  x = true, y = true, tx = true, ty = true, w = true, h = true,
  anchor = true, slack = true, tw = true, color = true,
}
-- Attributes the container can set as defaults for all its annotations.
local DEFAULT_KEYS = { "w", "h", "anchor", "slack", "tw", "color" }

local DEFAULTS = { w = "0.1", h = "0.1", anchor = "auto", slack = "0.5" }

local ANCHORS = { auto = true, left = true, right = true, top = true, bottom = true, center = true }

local dependency_added = false

local function warn(msg)
  quarto.log.warning("[image-callout] " .. msg)
end

local function num(value, name)
  if value == nil or value == "" then return nil end
  local s = tostring(value)
  local pct = s:match("^%s*([%+%-]?[%d%.]+)%s*%%%s*$")
  local n = pct and (tonumber(pct) and tonumber(pct) / 100) or tonumber(s)
  if n == nil then warn("cannot parse " .. name .. "='" .. s .. "' as a number") end
  return n
end

-- format a fraction (0-1) as a percentage number with limited precision
local function pc(v)
  local s = string.format("%.3f", v * 100)
  s = s:gsub("0+$", ""):gsub("%.$", "")
  if s == "-0" then s = "0" end
  return s
end

local function sign(v)
  return v < 0 and -1 or 1
end

local function merge_style(attributes, extra)
  if extra == "" then return end
  local old = attributes.style
  if old and old ~= "" then
    if not old:match(";%s*$") then old = old .. ";" end
    attributes.style = old .. extra
  else
    attributes.style = extra
  end
end

local function is_blank(blocks)
  return #blocks == 0 or pandoc.utils.stringify(blocks):match("^%s*$") ~= nil
end

-- Geometry of one callout, in fractions of the image size.
local function geometry(p)
  local rx, ry = p.w / 2, p.h / 2
  local dx, dy = p.tx - p.x, p.ty - p.y
  local anchor = p.anchor

  local horizontal
  if anchor == "left" or anchor == "right" then
    horizontal = true
  elseif anchor == "top" or anchor == "bottom" then
    horizontal = false
  else
    -- compare the free gaps outside the ellipse, so that a wide ellipse
    -- with text below it gets a vertical leader
    horizontal = (math.abs(dx) - rx) >= (math.abs(dy) - ry)
  end
  if anchor == "auto" then
    if horizontal then
      anchor = dx >= 0 and "left" or "right"
    else
      anchor = dy >= 0 and "top" or "bottom"
    end
  end

  -- start on the ellipse vertex facing the text, leaving perpendicular to it;
  -- end on (tx, ty), entering the text box from its anchor side.
  local sx, sy, c1x, c1y, c2x, c2y
  local ex, ey = p.tx, p.ty
  if horizontal then
    local out = sign(dx)
    sx, sy = p.x + out * rx, p.y
    local arm = p.slack * math.abs(ex - sx)
    local into = (anchor == "right") and -1 or (anchor == "left" and 1 or out)
    c1x, c1y = sx + out * arm, sy
    c2x, c2y = ex - into * arm, ey
  else
    local out = sign(dy)
    sx, sy = p.x, p.y + out * ry
    local arm = p.slack * math.abs(ey - sy)
    local into = (anchor == "bottom") and -1 or (anchor == "top" and 1 or out)
    c1x, c1y = sx, sy + out * arm
    c2x, c2y = ex, ey - into * arm
  end

  return {
    rx = rx, ry = ry, anchor = anchor,
    path = string.format("M %s %s C %s %s, %s %s, %s %s",
      pc(sx), pc(sy), pc(c1x), pc(c1y), pc(c2x), pc(c2y), pc(ex), pc(ey)),
  }
end

local function build_item(div, defaults)
  local a = div.attributes
  local function get(key)
    local v = a[key]
    if v == nil or v == "" then v = defaults[key] end
    if v == nil or v == "" then v = DEFAULTS[key] end
    return v
  end

  local p = {
    x = num(a.x, "x"), y = num(a.y, "y"),
    tx = num(a.tx, "tx"), ty = num(a.ty, "ty"),
    w = num(get("w"), "w") or 0.1, h = num(get("h"), "h") or 0.1,
    slack = num(get("slack"), "slack") or 0.5,
    anchor = get("anchor"),
  }
  if p.x == nil or p.y == nil then
    warn("annotation without x/y: placing the ellipse at the image centre")
    p.x, p.y = p.x or 0.5, p.y or 0.5
  end
  if not ANCHORS[p.anchor] then
    warn("unknown anchor '" .. tostring(p.anchor) .. "', using auto")
    p.anchor = "auto"
  end
  local has_text = p.tx ~= nil and p.ty ~= nil
  if not has_text and not is_blank(div.content) then
    warn("annotation has text but no tx/ty: only the ellipse is drawn")
  end

  local svg = {
    '<svg class="ic-svg" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true" focusable="false">',
  }
  local g
  if has_text then
    g = geometry(p)
    svg[#svg + 1] = string.format(
      '<path class="ic-leader" vector-effect="non-scaling-stroke" d="%s"/>', g.path)
  end
  svg[#svg + 1] = string.format(
    '<ellipse class="ic-ellipse" vector-effect="non-scaling-stroke" cx="%s" cy="%s" rx="%s" ry="%s"/>',
    pc(p.x), pc(p.y), pc(p.w / 2), pc(p.h / 2))
  svg[#svg + 1] = "</svg>"

  local blocks = { pandoc.RawBlock("html", table.concat(svg)) }

  if has_text then
    local style = string.format("left:%s%%;top:%s%%;", pc(p.tx), pc(p.ty))
    local tw = num(get("tw"), "tw")
    if tw then style = style .. string.format("width:%s%%;max-width:none;", pc(tw)) end
    blocks[#blocks + 1] = pandoc.Div(div.content,
      pandoc.Attr("", { "ic-text", "ic-anchor-" .. g.anchor }, { style = style }))
  end

  -- wrapper: keeps the user's id, extra classes (e.g. .fragment) and
  -- attributes (e.g. fragment-index) so that the whole callout behaves as one.
  local classes = pandoc.List({ "ic-item" })
  for _, c in ipairs(div.classes) do
    if c ~= ITEM_CLASS then classes:insert(c) end
  end
  local attrs = {}
  for k, v in pairs(a) do
    if not ITEM_KEYS[k] then attrs[k] = v end
  end
  local color = get("color")
  if color then merge_style(attrs, "--ic-accent:" .. color .. ";") end

  return pandoc.Div(blocks, pandoc.Attr(div.identifier, classes, attrs))
end

-- Find the image: a Para/Plain holding a single Image, or a Figure.
local function extract_image(block)
  if block.t == "Para" or block.t == "Plain" then
    local img
    for _, inl in ipairs(block.content) do
      if inl.t == "Image" and not img then
        img = inl
      elseif inl.t ~= "Space" and inl.t ~= "SoftBreak" and inl.t ~= "LineBreak" then
        return nil
      end
    end
    if img then return img, nil end
  elseif block.t == "Figure" then
    local img
    block.content:walk({ Image = function(i) img = img or i end })
    if img then
      local caption = block.caption and block.caption.long or nil
      return img, caption
    end
  end
  return nil
end

-- Natural size of a local image, as "W / H" (nil when unknown).
local function image_ratio(src)
  if not (pandoc.image and pandoc.image.size) then return nil end
  if src:match("^%a[%w+.-]*:") then return nil end -- URLs, data: URIs
  local ok, _, data = pcall(pandoc.mediabag.fetch, src)
  if not ok or not data then return nil end
  local ok2, size = pcall(pandoc.image.size, data)
  if not ok2 or not size or not size.width or not size.height or size.height == 0 then
    return nil
  end
  return string.format("%d / %d", size.width, size.height)
end

local auto_stretch = true

local function process(el, top_level)
  local img, caption
  local items = pandoc.List()
  local rest = pandoc.List()
  local defaults = {}
  for _, k in ipairs(DEFAULT_KEYS) do defaults[k] = el.attributes[k] end

  for _, b in ipairs(el.content) do
    if b.t == "Div" and b.classes:includes(ITEM_CLASS) then
      items:insert(b)
    elseif not img then
      local i, c = extract_image(b)
      if i then img, caption = i, c else rest:insert(b) end
    else
      rest:insert(b)
    end
  end

  if not img then
    warn("no image found in ." .. CONTAINER_CLASS .. " div; leaving it unchanged")
    return nil
  end

  if not dependency_added then
    quarto.doc.add_html_dependency({
      name = "image-callout",
      version = "0.1.0",
      stylesheets = { "image-callout.css" },
      scripts = quarto.doc.is_format("revealjs") and { "image-callout.js" } or nil,
    })
    dependency_added = true
  end

  local sized = img.attributes.width ~= nil or img.attributes.height ~= nil

  -- Like Quarto's auto-stretch for a lone image: a top-level, unsized
  -- image-callout fills the remaining slide height. The class must NOT be
  -- .r-stretch/.stretch in the HTML: Quarto's postprocessor would move the
  -- <img> out of the container. image-callout.js turns .ic-stretch into
  -- reveal's .r-stretch at runtime.
  local classes = pandoc.List()
  local stretch = false
  for _, c in ipairs(el.classes) do
    if c == "r-stretch" or c == "stretch" then stretch = true else classes:insert(c) end
  end
  if not stretch and top_level and auto_stretch and not sized
      and not classes:includes("nostretch") then
    stretch = true
  end
  stretch = stretch and quarto.doc.is_format("revealjs")
  if stretch then classes:insert("ic-stretch") end

  local stage_classes = pandoc.List({ "ic-stage" })
  local stage_style = ""
  local ratio = image_ratio(img.src)
  if ratio then
    stage_classes:insert("ic-ratio")
    stage_style = "--ic-ratio:" .. ratio .. ";"
  end

  -- A percentage width on the image refers to the slide/page: move it to the
  -- stage, and let the image fill the stage.
  local width = img.attributes.width
  if not stretch and width and width:match("%%%s*$") then
    stage_style = stage_style .. "width:" .. width .. ";"
    img.attributes.width = nil
    stage_classes:insert("ic-sized")
  end
  img.classes:insert("ic-image")

  local stage_content = pandoc.List({ pandoc.Plain({ img }) })
  for _, item in ipairs(items) do
    stage_content:insert(build_item(item, defaults))
  end

  local stage_attrs = {}
  if stage_style ~= "" then stage_attrs.style = stage_style end
  local stage = pandoc.Div(stage_content, pandoc.Attr("", stage_classes, stage_attrs))
  if stretch then
    -- size container, so that the stage can be fitted in it
    stage = pandoc.Div({ stage }, pandoc.Attr("", { "ic-frame" }))
  end

  local out = pandoc.List({ stage })
  if caption and not is_blank(caption) then
    out:insert(pandoc.Div(caption, pandoc.Attr("", { "ic-caption" })))
  end
  out:extend(rest)

  local attrs = {}
  for k, v in pairs(el.attributes) do
    if not ITEM_KEYS[k] then attrs[k] = v end
  end
  return pandoc.Div(out, pandoc.Attr(el.identifier, classes, attrs))
end

local function is_container(el)
  return el.t == "Div" and el.classes:includes(CONTAINER_CLASS)
end

return {
  {
    Pandoc = function(doc)
      if not quarto.doc.is_format("html:js") then return nil end
      if doc.meta["auto-stretch"] == false then auto_stretch = false end

      -- top-level containers become direct children of the slide <section>,
      -- the only place where reveal's .r-stretch works
      for i, b in ipairs(doc.blocks) do
        if is_container(b) then
          doc.blocks[i] = process(b, true) or b
          doc.blocks[i].attributes["__ic_done"] = "1"
        end
      end
      doc.blocks = doc.blocks:walk({
        Div = function(el)
          if el.attributes["__ic_done"] then
            el.attributes["__ic_done"] = nil
            return el
          end
          if is_container(el) then return process(el, false) end
        end,
      })
      return doc
    end,
  },
}
