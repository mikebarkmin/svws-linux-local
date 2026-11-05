-- Hyprland (Lua config): hide the empty "SchILD-NRW 3" window.
-- Delphi's TApplication window is 0x0 on Windows; under Wine/XWayland Hyprland
-- shows it as a floating window with a default size → park it on a hidden workspace.
hl.window_rule({
    name = "schild-hide-tapplication",
    match = { class = "^schild30\\.exe$", title = "^SchILD-NRW 3$" },
    workspace = "special:schild-hidden silent",
    no_initial_focus = true,
})
