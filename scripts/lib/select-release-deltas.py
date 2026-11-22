"""Copy the signed patches for one build from Sparkle's generated feed."""
from pathlib import Path
import re
import shutil
import sys
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
NS = {"sparkle": SPARKLE}


def select(feed, build, archives, destination):
    items = [item for item in ET.parse(feed).findall("channel/item")
             if item.findtext("sparkle:version", namespaces=NS) == build]
    if len(items) != 1:
        raise ValueError(f"Expected one generated Sparkle item for build {build}")
    groups = items[0].findall("sparkle:deltas", NS)
    if not groups:
        return
    if len(groups) != 1:
        raise ValueError(f"Multiple delta groups on build {build}")
    files = []
    for enclosure in groups[0].findall("enclosure"):
        source = enclosure.get(f"{{{SPARKLE}}}deltaFrom", "")
        name = enclosure.get("url", "").rsplit("/", 1)[-1]
        if not re.fullmatch(r"[0-9]+", source) or name != f"YEN{build}-{source}.delta":
            raise ValueError(f"Unexpected patch for build {build}: {name}")
        patch = archives / name
        if patch in files or patch.stat().st_size != int(enclosure.attrib["length"]):
            raise ValueError(f"Duplicate patch or incorrect size: {name}")
        files.append(patch)
    for patch in files:
        shutil.copy2(patch, destination / patch.name)
    if files:
        ET.register_namespace("sparkle", SPARKLE)
        print(ET.tostring(groups[0], encoding="unicode").strip())


if __name__ == "__main__":
    select(Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3]), Path(sys.argv[4]))
