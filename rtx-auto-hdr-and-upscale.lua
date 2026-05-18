-- RTX Auto HDR & Upscale for Plex/mpv
-- https://mpv.io/manual/master/

local mp = require 'mp'

-- === CONFIG ===
local HDR_WHITE   = 800     -- hdr-reference-white when display is HDR (nits)
local HDR_PEAK    = 800     -- target-peak when display is HDR (nits)
local HDR_RECOVER = 0.3     -- hdr-contrast-recovery strength when display is HDR
local ROUND_DP    = 2       -- decimal places for scale factor
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

-- === RTX FILTER MANAGEMENT ===

local function apply_rtx()
    if applying then return end

    local dw = mp.get_property_native("display-width")
    local dh = mp.get_property_native("display-height")
    local vw = mp.get_property_native("width")
    local vh = mp.get_property_native("height")
    local gamma = mp.get_property("video-target-params/gamma")
    local content_gamma = mp.get_property("video-params/gamma")

    if not dw or not dh or not vw or not vh or not gamma or gamma == "" or not content_gamma or content_gamma == "" then
        return
    end

    applying = true

    local is_display_hdr = (gamma == "pq" or gamma == "hlg")
    local is_content_hdr = (content_gamma:lower() == "pq" or content_gamma:lower() == "hlg")
    local use_true_hdr = auto_hdr_enabled and not is_content_hdr and is_display_hdr

    local params = {}
    local scale

    if vsr_enabled then
        scale = round(math.max(dw, dh) / math.max(vw, vh), ROUND_DP)
        if scale > 1 then
            table.insert(params, "scaling-mode=nvidia:scale=" .. scale)
        end
    end

    if use_true_hdr then
        table.insert(params, "nvidia-true-hdr=yes")
    end

    local new_filter = ""
    if #params > 0 then
        new_filter = "@rtx:d3d11vpp=" .. table.concat(params, ":")
    end

    local vf = mp.get_property("vf") or ""
    local has_rtx_filter = vf:find("@rtx")
    local current_filter = ""

    if has_rtx_filter then
        -- extract the current @rtx filter string to compare
        for filter in string.gmatch(vf, "[^,]+") do
            if filter:find("@rtx") then
                current_filter = filter
                break
            end
        end
    end

    if new_filter == current_filter then
        applying = false
        return
    end

    if has_rtx_filter then
        mp.commandv("vf", "remove", "@rtx")
    end

    if new_filter ~= "" then
        mp.commandv("vf", "append", new_filter)
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

-- === HDR DISPLAY PROPERTIES ===
-- Sets target-peak, inverse-tone-mapping, hdr-contrast-recovery only when
-- the display is actually in HDR mode. target-peak > 203 in SDR forces mpv
-- into HDR-like processing, so these must be conditional.

local last_display_hdr = nil

local function sync_hdr_display()
    local gamma = mp.get_property("video-target-params/gamma")
    if not gamma or gamma == "" then return end

    local is_hdr = (gamma == "pq" or gamma == "hlg")

    if is_hdr == last_display_hdr then return end
    last_display_hdr = is_hdr

    if is_hdr then
        mp.set_property_number("target-peak", HDR_PEAK)
        mp.set_property_number("hdr-contrast-recovery", HDR_RECOVER)
        mp.set_property_bool("inverse-tone-mapping", true)
    else
        mp.set_property("target-peak", "auto")
        mp.set_property_number("hdr-contrast-recovery", 0)
        mp.set_property_bool("inverse-tone-mapping", false)
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

local TONEMAP_CYCLE = { "auto", "bt.2446a", "st2094-40", "spline", "hable" }
local tonemap_idx = 1

local function toggle_tonemapping()
    tonemap_idx = tonemap_idx % #TONEMAP_CYCLE + 1
    local tm = TONEMAP_CYCLE[tonemap_idx]
    mp.set_property("tone-mapping", tm)
    mp.osd_message("Tone-mapping: " .. tm)
end

local function toggle_compute_peak()
    local cur = mp.get_property_bool("hdr-compute-peak")
    mp.set_property_bool("hdr-compute-peak", not cur)
    mp.osd_message("hdr-compute-peak: " .. (not cur and "ON" or "OFF"))
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
    local tm           = mp.get_property("tone-mapping") or "nil"
    local cpeak        = mp.get_property("hdr-compute-peak") or "nil"
    local crecov       = mp.get_property("hdr-contrast-recovery") or "nil"
    local tpeak        = mp.get_property("target-peak") or "nil"
    local itm          = mp.get_property("inverse-tone-mapping") or "nil"

    mp.osd_message(string.format(
        "target gamma: %s\nsource gamma: %s\npixfmt: %s\nhwdec: %s\n" ..
        "hdr-ref-white: %s\ntone-mapping: %s\nhdr-compute-peak: %s\n" ..
        "hdr-contrast-recovery: %s\ntarget-peak: %s\ninverse-tone-mapping: %s\n" ..
        "rtx filter: %s\nvsr: %s | auto_hdr: %s",
        target_gamma, source_gamma, pixfmt, hwdec_cur, refwhite, tm, cpeak,
        crecov, tpeak, itm, has_rtx, tostring(vsr_enabled), tostring(auto_hdr_enabled)
    ), 6)
end

-- === INIT ===

apply_rtx()
mp.observe_property("video-params/pixelformat", "native", apply_rtx)
mp.observe_property("video-target-params/gamma", "string", apply_rtx)

sync_hdr_white()
mp.observe_property("video-target-params/gamma", "string", sync_hdr_white)
mp.register_event("file-loaded", sync_hdr_white)

sync_hdr_display()
mp.observe_property("video-target-params/gamma", "string", sync_hdr_display)
mp.register_event("file-loaded", sync_hdr_display)

mp.add_key_binding("alt+u", "toggle_vsr", toggle_vsr)
mp.add_key_binding("alt+h", "toggle_auto_hdr", toggle_auto_hdr)
mp.add_key_binding("alt+w", "toggle_whitepoint", toggle_whitepoint)
mp.add_key_binding("alt+b", "cycle_brightness", cycle_brightness)
mp.add_key_binding("alt+c", "toggle_tonemapping", toggle_tonemapping)
mp.add_key_binding("alt+p", "toggle_compute_peak", toggle_compute_peak)
mp.add_key_binding("alt+j", "show_debug_osd", show_debug_osd)
