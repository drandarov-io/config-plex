# Plex config for HDR and RTX features

mpv Lua script for Plex that enables NVIDIA RTX video processing features and fixes HDR.

## input.conf

Custom keybindings beyond the script defaults:

| Key | Action |
| --- | --- |
| `Alt+I` | Toggle stats/information overlay |
| `` ` `` | Open mpv console |
| `.` | Frame step forward |
| `,` | Frame step backward |
| `Ctrl+Left` | Seek 5s backward (exact) |
| `Ctrl+Right` | Seek 5s forward (exact) |
| `-` | Decrease playback speed by 0.1x |
| `=` | Increase playback speed by 0.1x |
| `0` | Reset playback speed to 1x |

## Features

## Requirements

- NVIDIA RTX GPU
- `hwdec=d3d11va`, `vo=gpu-next`, and `gpu-api=d3d11` in `mpv.conf` (these might be the default by the time you read this)
- Up to date v0.41.0+ [mpv build](https://github.com/shinchiro/mpv-winbuild-cmake/releases) / [mpv build alt.](https://github.com/zhongfly/mpv-winbuild/releases) (`mpv-dev-x86_64-v3`)

## Keybindings

| Key | Action |
| --- | --- |
| `Alt+U` | Toggle RTX Upscale on/off |
| `Alt+H` | Toggle RTX Auto HDR on/off |
| `Alt+J` | Show debug OSD (target gamma, ref white, filter state) |

### RTX Upscale (VSR)

Enables RTX video upscale match display resolution. The scale factor is computed as `max(display_dim) / max(video_dim)` — e.g. 1080p content on a 4K display gets a 2.0x factor. Only applies when the video is lower resolution than the display.

- **Default:** ON
- **Toggle:** `Alt+U`
- Requires `hwdec=d3d11va` in `mpv.conf`

### RTX Auto HDR

⚠️ Currently broken due to [mpv issue #17265](https://github.com/mpv-player/mpv/issues/17265)

Enables NVIDIA RTX Auto HDR (`nvidia-true-hdr`) which converts SDR content to HDR. Integrated into the same d3d11vpp filter. Automatically skipped for native HDR content (True HDR is SDR→HDR only).

- **Default:** ON
- **Toggle:** `Alt+H`
- Requires `gpu-api=d3d11` in `mpv.conf`
- Requires NVIDIA Control Panel → Adjust video image settings → RTX Video → **RTX Video HDR** enabled

### HDR White Point

Automatically adjusts `hdr-reference-white` based on display HDR state:

Edit the constants at the top of the script to match your monitor:

```lua
local HDR_WHITE = 800   -- hdr-reference-white when display is HDR (nits)
```

| Display mode | `hdr-reference-white` |
| --- | --- |
| HDR (PQ/HLG) | 800 nits |
| SDR | 203 nits (mpv default) |

Detection uses `video-target-params/gamma` — the actual output transfer function negotiated between mpv and the display via the D3D11 swapchain.
