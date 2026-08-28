#!/usr/bin/env python3
"""Add a full-screen image layer to an Apple native wallpaper CAML file."""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path


NS = "http://www.apple.com/CoreAnimation/1.0"
ET.register_namespace("", NS)


def q(name: str) -> str:
    return f"{{{NS}}}{name}"


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: overlay-native-caml.py MAIN_CAML")

    caml_path = Path(sys.argv[1])
    tree = ET.parse(caml_path)
    root = tree.getroot()

    floating = next(
        (
            layer
            for layer in root.iter(q("CALayer"))
            if layer.attrib.get("name") == "FLOATING"
        ),
        None,
    )
    if floating is None:
        raise RuntimeError("The native CAML file has no FLOATING layer")

    sublayers = floating.find(q("sublayers"))
    if sublayers is None:
        sublayers = ET.SubElement(floating, q("sublayers"))

    for layer in list(sublayers):
        if layer.attrib.get("name") == "Morrow Full Screen":
            sublayers.remove(layer)

    image_layer = ET.SubElement(
        sublayers,
        q("CALayer"),
        {
            "id": "morrow-full-screen",
            "name": "Morrow Full Screen",
            "bounds": "0 0 393 852",
            "position": "196.5 426",
            "geometryFlipped": "0",
            "masksToBounds": "0",
            "opacity": "1",
            "allowsEdgeAntialiasing": "1",
            "allowsGroupOpacity": "1",
            "contentsFormat": "RGBA8",
            "cornerCurve": "circular",
        },
    )
    contents = ET.SubElement(image_layer, q("contents"))
    ET.SubElement(contents, q("CGImage"), {"src": "assets/morrow.png"})

    tree.write(caml_path, encoding="UTF-8", xml_declaration=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
