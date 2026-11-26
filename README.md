# PipeWire Top Plasmoid

A KDE Plasma 6 widget that shows what PipeWire is doing right now: the quantum, sample rate, and sample format of every running audio device and the streams attached to it. It is a live view of `pw-top`, drawn directly in your panel or on the desktop.

## What it shows

One row per running node, refreshed every second:

| Column | Meaning |
| ------ | ------- |
| QUANT  | Buffer size (quantum) in samples |
| RATE   | Graph sample rate in Hz |
| FORMAT | Sample format, channel count, and sample rate (for example `S32LE 2 48000`) |
| NAME   | Device description; streams playing through a device are listed under it with a `+` prefix |

Hovering the widget shows a tooltip with more detail per node: channel count, bitrate, latency in milliseconds, and the xrun count when there are any.

The layout adapts to where the widget lives:

- **Horizontal panel:** a compact table without a header; the text shrinks so all rows fit the panel height.
- **Vertical panel:** each node is a small stacked block.
- **Desktop:** the full table with a header row.

When nothing is playing, the widget collapses to a dimmed sound card icon. If `pw-top` fails, it shows a warning icon and the error appears in the tooltip.

## Requirements

- KDE Plasma 6.0 or later
- PipeWire, with the `pw-top` and `pw-dump` tools on your `PATH` (usually part of the `pipewire` package)
- The Plasma 5 support library (`plasma5support`), which most Plasma 6 installs already have

## Install

```sh
git clone https://github.com/cheese-greater/PipeWire-Top-Plasmoid.git
cd PipeWire-Top-Plasmoid
kpackagetool6 -t Plasma/Applet -i package
```

Then right-click a panel or the desktop, choose **Add Widgets**, and search for **PipeWire Top**.

To update after pulling new changes:

```sh
kpackagetool6 -t Plasma/Applet -u package
```

To remove it:

```sh
kpackagetool6 -t Plasma/Applet -r io.pwtop.plasmoid
```

If an update does not show up, restart the shell with `systemctl --user restart plasma-plasmashell`.

## Development

The widget is two files:

- `package/contents/ui/main.qml`: polling and layout
- `package/contents/code/pwtop.js`: parsing of `pw-top` and `pw-dump` output, and value formatting

To try changes without installing, run the widget in a standalone window (needs the `plasma-sdk` package):

```sh
plasmoidviewer -a package
```

Add `-f horizontal` or `-f vertical` to preview the panel layouts.

## License

[MIT](LICENSE)
