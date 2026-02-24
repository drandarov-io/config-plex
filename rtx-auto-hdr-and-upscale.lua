-- RTX Auto HDR & Upscale for Plex/mpv
-- https://mpv.io/manual/master/

local mp = require 'mp'

-- === CONFIG ===
local HDR_WHITE = 800       -- hdr-reference-white when display is HDR (nits)
local SDR_WHITE = 203       -- hdr-reference-white when display is SDR (nits)
local ROUND_DP  = 3         -- decimal places for scale factor

-- Runtime state
local vsr_enabled      = true   -- RTX upscale on by default
local auto_hdr_enabled = true   -- RTX Auto HDR on by default
local white_is_hdr     = nil    -- nil = auto, true/false = manual override
local applying         = false  -- re-entrancy guard

-- === HELPERS ===

local function round(value, dp)
    local m = 10 ^ dp
    return math.floor(value * m + 0.5) / m
end

-- Detect if mpv negotiated an HDR swapchain with the display.
local function is_display_hdr()
    local gamma = mp.get_property("video-target-params/gamma") or ""
    return gamma == "pq" or gamma == "hlg"
end

-- Detect if the source video is HDR (True HDR is SDR→HDR only).
local function is_content_hdr()
    local gamma = (mp.get_property("video-params/gamma") or ""):lower()
    return gamma == "pq" or gamma == "hlg"
end

-- === RTX UPSCALE (VSR) + AUTO HDR ===

local function remove_vsr_filter()
    local vf = mp.get_property("vf") or ""
    if vf:find("@vsr") then
        mp.commandv("vf", "remove", "@vsr")
    end
end

local function apply_vsr()
    if applying then return end
    applying = true

    remove_vsr_filter()

    if not vsr_enabled then
        applying = false
        return
    end

    local dw = mp.get_property_native("display-width")
    local dh = mp.get_property_native("display-height")
    local vw = mp.get_property_native("width")
    local vh = mp.get_property_native("height")

    if not (dw and dh and vw and vh) then
        mp.msg.warn("Missing resolution, skipping RTX upscale")
        applying = false
        return
    end

    local scale = round(math.max(dw, dh) / math.max(vw, vh), ROUND_DP)

    if scale <= 1 then
        mp.msg.info("No upscale needed (scale " .. scale .. ")")
        applying = false
        return
    end

    -- Build filter: RTX VSR with optional Auto HDR (SDR content only)
    local filter = "@vsr:d3d11vpp=scaling-mode=nvidia:scale=" .. scale
    local use_true_hdr = auto_hdr_enabled and not is_content_hdr()
    if use_true_hdr then
        filter = filter .. ":nvidia-true-hdr=yes"
    end

    mp.commandv("vf", "append", filter)

    local msg = "RTX Upscale: " .. scale .. "x"
    if auto_hdr_enabled then
        msg = msg .. (use_true_hdr and "  Auto HDR: ON" or "  Auto HDR: skipped (HDR source)")
    end
    mp.osd_message(msg)
    applying = false
end

-- === HDR WHITE POINT ===

local function sync_hdr_white()
    local hdr
    if white_is_hdr ~= nil then hdr = white_is_hdr else hdr = is_display_hdr() end
    mp.set_property_number("hdr-reference-white", hdr and HDR_WHITE or SDR_WHITE)
end

-- === TOGGLES ===

local function toggle_vsr()
    vsr_enabled = not vsr_enabled
    if vsr_enabled then
        apply_vsr()
        mp.observe_property("video-params/pixelformat", "native", apply_vsr)
    else
        remove_vsr_filter()
        mp.unobserve_property(apply_vsr)
    end
    mp.osd_message("RTX Upscale: " .. (vsr_enabled and "ON" or "OFF"))
end

local function toggle_auto_hdr()
    auto_hdr_enabled = not auto_hdr_enabled
    apply_vsr()
    mp.osd_message("RTX Auto HDR: " .. (auto_hdr_enabled and "ON" or "OFF"))
end

local function toggle_whitepoint()
    local current
    if white_is_hdr ~= nil then current = white_is_hdr else current = is_display_hdr() end
    white_is_hdr = not current
    sync_hdr_white()
    mp.osd_message("Whitepoint: " .. (white_is_hdr and HDR_WHITE or SDR_WHITE) .. " nits")
end

-- === DEBUG OSD ===

local function show_debug_osd()
    local target_gamma = mp.get_property("video-target-params/gamma") or "nil"
    local source_gamma = mp.get_property("video-params/gamma") or "nil"
    local pixfmt       = mp.get_property("video-params/pixelformat") or "nil"
    local refwhite     = mp.get_property("hdr-reference-white") or "nil"
    local hwdec_cur    = mp.get_property("hwdec-current") or "nil"
    local vf           = mp.get_property("vf") or ""
    local has_vsr      = string.match(vf, "@vsr") and "yes" or "no"

    mp.osd_message(string.format(
        "target gamma: %s\nsource gamma: %s\npixfmt: %s\nhwdec: %s\nhdr-ref-white: %s\nvsr filter: %s\nvsr: %s | auto_hdr: %s",
        target_gamma, source_gamma, pixfmt, hwdec_cur, refwhite, has_vsr,
        tostring(vsr_enabled), tostring(auto_hdr_enabled)
    ), 6)
end

-- === INIT ===

apply_vsr()
mp.observe_property("video-params/pixelformat", "native", apply_vsr)

sync_hdr_white()
mp.observe_property("video-target-params/gamma", "string", sync_hdr_white)
mp.register_event("file-loaded", sync_hdr_white)

mp.add_key_binding("alt+u", "toggle_vsr", toggle_vsr)
mp.add_key_binding("alt+h", "toggle_auto_hdr", toggle_auto_hdr)
mp.add_key_binding("alt+w", "toggle_whitepoint", toggle_whitepoint)
mp.add_key_binding("alt+j", "show_debug_osd", show_debug_osd)
