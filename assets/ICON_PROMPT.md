# VoiceDeck icon

Current asset: [`Sources/VoiceDeck/Resources/AppIcon.png`](../Sources/VoiceDeck/Resources/AppIcon.png).

The icon follows ModelDeck’s native vector design: a dark rounded square (`0.055, 0.085, 0.09` RGB), mint strokes (`0.40, 0.88, 0.72`), a transparent margin and rounded line caps. Five waveform bars identify VoiceDeck; the lower chevron recalls the shared Deck family.

The artwork is drawn with AppKit, without external assets or a generative model. Recreate the master PNG:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift scripts/draw-icon.swift Sources/VoiceDeck/Resources/AppIcon.png
```

`scripts/generate-icon.swift` resizes and packages the PNG into the standard macOS ICNS representations. The earlier imagegen artwork was replaced in version 0.3.0 at the author’s request.
