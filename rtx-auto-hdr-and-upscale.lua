-- RTX Auto HDR & Upscale for Plex/mpv
-- https://mpv.io/manual/master/

local mp = require 'mp'

-- === CONFIG ===
local HDR_WHITE = 800       -- hdr-reference-white when display is HDR (nits)
local ROUND_DP  = 3         -- decimal places for scale factor
local BRIGHTNESS_STEPS = { 2.5, 5, 7.5, 10, 15 }  -- brightness boost cycle values

-- Runtime state
local vsr_enabled      = true   -- RTX upscale on by default
local auto_hdr_enabled = true   -- RTX Auto HDR on by default
local white_is_hdr     = nil    -- nil = auto, true/false = manual override
local brightness_idx   = 0      -- 0 = off, 1..#BRIGHTNESS_STEPS = active step
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

-- === RTX FILTER MANAGEMENT ===

local function remove_rtx_filter()
    local vf = mp.get_property("vf") or ""
    if vf:find("@rtx") then
        mp.commandv("vf", "remove", "@rtx")
    end
end

local function apply_rtx()
    if applying then return end
    applying = true

    remove_rtx_filter()

    local use_true_hdr = auto_hdr_enabled and not is_content_hdr()

    if not vsr_enabled and not use_true_hdr then
        applying = false
        return
    end

    local params = {}
    local scale

    if vsr_enabled then
        local dw = mp.get_property_native("display-width")
        local dh = mp.get_property_native("display-height")
        local vw = mp.get_property_native("width")
        local vh = mp.get_property_native("height")

        if dw and dh and vw and vh then
            scale = round(math.max(dw, dh) / math.max(vw, vh), ROUND_DP)
            if scale > 1 then
                table.insert(params, "scaling-mode=nvidia:scale=" .. scale)
            else
                mp.msg.info("No upscale needed (scale " .. scale .. ")")
            end
        else
            mp.msg.warn("Missing resolution, skipping RTX upscale")
        end
    end

    if use_true_hdr then
        table.insert(params, "nvidia-true-hdr=yes")
    end

    if #params > 0 then
        local filter = "@rtx:d3d11vpp=" .. table.concat(params, ":")
        mp.commandv("vf", "append", filter)
    end

    local msg = {}
    if vsr_enabled and scale and scale > 1 then
        table.insert(msg, "RTX Upscale: " .. scale .. "x")
    end
    if auto_hdr_enabled then
        table.insert(msg, use_true_hdr and "Auto HDR: ON" or "Auto HDR: skipped (HDR source)")
    end
    if #msg > 0 then
        mp.osd_message(table.concat(msg, "  "))
    end

    applying = false
end

-- === HDR WHITE POINT ===

local function sync_hdr_white()
    if white_is_hdr then
        mp.set_property_number("hdr-reference-white", HDR_WHITE)
    else
        mp.set_property("hdr-reference-white", "auto")
    end
end

-- === TOGGLES ===

local function toggle_vsr()
    vsr_enabled = not vsr_enabled
    apply_rtx()
    mp.osd_message("RTX Upscale: " .. (vsr_enabled and "ON" or "OFF"))
end

local function toggle_auto_hdr()
    auto_hdr_enabled = not auto_hdr_enabled
    apply_rtx()
    mp.osd_message("RTX Auto HDR: " .. (auto_hdr_enabled and "ON" or "OFF"))
end

local function toggle_whitepoint()
    white_is_hdr = not white_is_hdr
    sync_hdr_white()
    mp.osd_message("Whitepoint: " .. (white_is_hdr and (HDR_WHITE .. " nits") or "auto"))
end

local function cycle_brightness()
    brightness_idx = brightness_idx + 1
    if brightness_idx > #BRIGHTNESS_STEPS then brightness_idx = 0 end

    if brightness_idx == 0 then
        mp.set_property_number("brightness", 0)
        mp.osd_message("Brightness boost: OFF")
    else
        local val = BRIGHTNESS_STEPS[brightness_idx]
        mp.set_property_number("brightness", val)
        mp.osd_message("Brightness boost: " .. val)
    end
end

-- === DEBUG OSD ===

local function show_debug_osd()
    local target_gamma = mp.get_property("video-target-params/gamma") or "nil"
    local source_gamma = mp.get_property("video-params/gamma") or "nil"
    local pixfmt       = mp.get_property("video-params/pixelformat") or "nil"
    local refwhite     = mp.get_property("hdr-reference-white") or "nil"
    local hwdec_cur    = mp.get_property("hwdec-current") or "nil"
    local vf           = mp.get_property("vf") or ""
    local has_rtx      = vf:find("@rtx") and "yes" or "no"

    mp.osd_message(string.format(
        "target gamma: %s\nsource gamma: %s\npixfmt: %s\nhwdec: %s\nhdr-ref-white: %s\nrtx filter: %s\nvsr: %s | auto_hdr: %s",
        target_gamma, source_gamma, pixfmt, hwdec_cur, refwhite, has_rtx,
        tostring(vsr_enabled), tostring(auto_hdr_enabled)
    ), 6)
end

-- === INIT ===

apply_rtx()
mp.observe_property("video-params/pixelformat", "native", apply_rtx)

sync_hdr_white()
mp.observe_property("video-target-params/gamma", "string", sync_hdr_white)
mp.register_event("file-loaded", sync_hdr_white)

mp.add_key_binding("alt+u", "toggle_vsr", toggle_vsr)
mp.add_key_binding("alt+h", "toggle_auto_hdr", toggle_auto_hdr)
mp.add_key_binding("alt+w", "toggle_whitepoint", toggle_whitepoint)
mp.add_key_binding("alt+b", "cycle_brightness", cycle_brightness)
mp.add_key_binding("alt+j", "show_debug_osd", show_debug_osd)
