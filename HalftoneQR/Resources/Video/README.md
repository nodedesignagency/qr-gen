# Background video

Drop the loop here as `background.mp4` (`.mov` and `.m4v` also work).

`VideoBackground` finds it by name, plays it muted and gapless via
`AVPlayerLooper`, and fills the screen with `.resizeAspectFill`. With no file
present it falls back to a still field in the same palette, so the layout is
never broken by a missing asset.

Keep it short and seamless — a few seconds is plenty, and the file ships inside
the app, so watch the size.
