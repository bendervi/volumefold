# VolumeFold

Automatically lowers your MacBook’s speaker volume as you close the lid and restores it when you reopen it.

## Requirements

- macOS 13 or newer.
- Xcode 15 or newer. Install it from the Mac App Store and open it once to finish setup.
- A MacBook with a readable hinge-angle sensor. Support varies by model.

## Install

Open Terminal and run:

```sh
git clone https://github.com/bendervi/volumefold.git
cd volumefold
./scripts/build.sh
mkdir -p ~/Applications
ditto "$(readlink build/VolumeFold.app)" ~/Applications/VolumeFold.app
open ~/Applications/VolumeFold.app
```

Already downloaded the project? Open Terminal in its folder and start with `./scripts/build.sh`.

## Use

Click the laptop icon in the menu bar to:

- Enable or disable VolumeFold.
- Set **Start fading below** (default: 80°).
- Show or hide the menu bar percentage.
- Enable **Launch at login**.

Works with built-in speakers only. If the panel says **Hinge sensor unavailable**, your Mac’s sensor may not be supported.
