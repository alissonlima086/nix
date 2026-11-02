-- ~/.config/hypr/hyprland.lua
-- Sintaxe real do Hyprland 0.55+ (hl.*)

local mainMod = "SUPER"
local terminal = "kitty"
local fileManager = "thunar"
local menu = "noctalia msg panel-toggle launcher"

-------------------
---- AUTOSTART ----
-------------------
hl.on("hyprland.start", function()
  hl.exec_cmd("~/.config/hypr/scripts/steam-audio-focus.sh")
  hl.exec_cmd("~/.config/hypr/scripts/zzz-mouse-autofix.py")
  hl.exec_cmd("noctalia")
  hl.exec_cmd("nm-applet")
  hl.exec_cmd("discord --start-minimized")
  hl.exec_cmd("steam -silent")
end)

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("GDK_BACKEND", "wayland")

-----------------------
---- LOOK AND FEEL ----
-----------------------
hl.config({
  general = {
    gaps_in = 5,
    gaps_out = 12,
    border_size = 2,
    col = {
      active_border = "rgba(cba6f7ff)",
      inactive_border = "rgba(585b70aa)",
    },
    resize_on_border = true,
    allow_tearing = false,
    layout = "dwindle",
  },

  decoration = {
    rounding = 12,
    active_opacity = 1.0,
    inactive_opacity = 1.0,
    shadow = {
      enabled = false,
      range = 20,
      render_power = 3,
      color = 0x55000000,
    },
    blur = {
      enabled = false,
      size = 6,
      passes = 2,
    },
  },

  animations = {
    enabled = true,
  },
})

hl.curve("easeOut", { type = "bezier", points = { { 0.25, 1 }, { 0.5, 1 } } })

hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "easeOut" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 4, bezier = "default", style = "popin 80%" })
hl.animation({ leaf = "border", enabled = true, speed = 5, bezier = "default" })
hl.animation({ leaf = "fade", enabled = true, speed = 4, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "default" })

---------------
---- INPUT ----
---------------
hl.config({
  input = {
    kb_layout = "br",
    kb_variant = "abnt2",
    follow_mouse = 1,
    sensitivity = 0,
    touchpad = {
      natural_scroll = false,
    },
  },
})

----------------
---- MISC ----
----------------
hl.config({
  misc = {
    animate_manual_resizes = false,
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
  },
})

---------------------
---- KEYBINDINGS ----
---------------------
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(
  mainMod .. " + M",
  hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'")
)
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))
-- fullscreen: dispatcher exato não confirmado na doc consultada; ajuste se necessário
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind(mainMod .. " + Y", hl.dsp.exec_cmd("~/.config/hypr/scripts/yt-play.sh"))
hl.bind("Print", hl.dsp.exec_cmd("hyprshot -m region -o ~/Pictures/screenshots"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("hyprshot -m output -o ~/Pictures/screenshots"))

-- focus
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

-- workspaces 1-9,0 + mover janela
for i = 1, 10 do
  local key = i % 10
  hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
  hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- special workspace
hl.bind("ALT + 1", hl.dsp.workspace.toggle_special("magic"))
hl.bind("ALT + SHIFT + 1", hl.dsp.window.move({ workspace = "special:magic" }))

-- scroll entre workspaces
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- mover/redimensionar com o mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

--------------------------------
---- WINDOW RULES ----
--------------------------------
hl.window_rule({
  name = "waterfox-pip",
  match = { title = "^(Picture-in-Picture)$" },
  float = true,
  size = "480 270",
  pin = true,
  move = "1040 780",
})

-- LibreOffice: impedir fullscreen automático
hl.window_rule({
  name = "libreoffice-tiled",
  match = { class = "^(libreoffice-.*)$" },
  fullscreen = false,
})
