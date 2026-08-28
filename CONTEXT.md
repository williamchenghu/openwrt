# Print Gateway (WR703N)

A minimal OpenWrt image effort for a modified TP-Link WR703N (8 MB flash, 64 MB
RAM) that joins an existing Wi-Fi network, keeps SSH administration, and
exposes a Brother DCP-1510 over USB for Mac/Windows printing. See
`docs/wayfinder/wr703n-print-gateway/` for the decision map.

## Language

**Print gateway**:
The device as configured by this effort: it joins an existing network and
exposes a USB printer to that network.
_Avoid_: print server, router

**Client mode**:
The gateway's Wi-Fi role: it joins an existing network as a station and never
acts as an access point.
_Avoid_: AP mode, repeater, dumb AP

**Upstream network / upstream router**:
The pre-existing network and router the gateway joins. The gateway hosts no
DHCP, DNS, NAT, or firewall of its own; it is a pure client of the upstream
router.

**br-lan**:
The gateway's single network bridge, carrying the wired port and the Wi-Fi
client link together, with one DHCP client on it.

**First-boot setup**:
The one-time provisioning of a network-agnostic image over its wired port via
LuCI — set the root password and configure the Wi-Fi client — after which the
device joins the upstream network.

**Breed**:
The device's bootloader, a replacement for stock U-Boot (hackpascal's
"Boot and Recovery Environment", aka 刷不死). It lives at flash offset
0x0–0x20000, exposes a web recovery console at 192.168.1.1 (entered by holding
the reset button on power-on, or automatically when firmware fails to boot),
and never writes the firmware or ART partitions unless asked to.
_Avoid_: U-Boot, bootloader partition (when the specific loader is meant)

**ART**:
The 64 KB flash partition at 0x7f0000–0x800000 holding the unit's unique WiFi
radio calibration (read by the device tree at ART+0x1000, 0x440 bytes).
Per-unit data: never baked into the image, backed up per device.
_Avoid_: calibration data, eeprom blob
