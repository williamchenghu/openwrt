#!/usr/bin/env python3
"""Regenerate build/patches/0099-usb-chipidea2-add-reset-handling.patch.

Edits ci_hdrc_usb2.c in the kernel build tree, then emits a clean unified
diff against a pristine copy. Run from the kernel build tree root
(build_dir/target-mips_24kc_musl/linux-ath79_tiny/linux-6.18.44):

    python3 /src/gen_patch.py
"""
import subprocess

path = "drivers/usb/chipidea/ci_hdrc_usb2.c"
src = open(path).read()

# 1. Add reset.h include
src = src.replace(
    "#include <linux/phy/phy.h>\n",
    "#include <linux/phy/phy.h>\n#include <linux/reset.h>\n",
    1,
)

# 2. Add rst field to priv struct
src = src.replace(
    "struct ci_hdrc_usb2_priv {\n\tstruct platform_device\t*ci_pdev;\n\tstruct clk\t\t*clk;\n};",
    "struct ci_hdrc_usb2_priv {\n\tstruct platform_device\t*ci_pdev;\n\tstruct clk\t\t*clk;\n\tstruct reset_control\t*rst;\n};",
    1,
)

# 3. Add reset deassert before clock enable in probe
old_probe = (
    "\tpriv->clk = devm_clk_get_optional(dev, NULL);\n"
    "\tif (IS_ERR(priv->clk))\n"
    "\t\treturn PTR_ERR(priv->clk);\n"
    "\n"
    "\tret = clk_prepare_enable(priv->clk);"
)
new_probe = (
    "\tpriv->clk = devm_clk_get_optional(dev, NULL);\n"
    "\tif (IS_ERR(priv->clk))\n"
    "\t\treturn PTR_ERR(priv->clk);\n"
    "\n"
    "\t/* Deassert the USB controller reset if present in DT.\n"
    "\t * On ath79 (AR9331 etc.) the USB controller is held in reset by\n"
    "\t * the reset controller at boot. Some bootloaders deassert this\n"
    "\t * reset before booting the kernel, but others (e.g. Breed) do\n"
    "\t * not. Without deasserting, all controller registers read 0 and\n"
    "\t * ci_hdrc_host_init() fails with -ENXIO (\"doesn't support host\").\n"
    "\t */\n"
    "\tpriv->rst = devm_reset_control_get_optional_exclusive(dev, NULL);\n"
    "\tif (IS_ERR(priv->rst)) {\n"
    "\t\tclk_disable_unprepare(priv->clk);\n"
    "\t\treturn PTR_ERR(priv->rst);\n"
    "\t}\n"
    "\n"
    "\tret = reset_control_deassert(priv->rst);\n"
    "\tif (ret) {\n"
    "\t\tclk_disable_unprepare(priv->clk);\n"
    "\t\treturn ret;\n"
    "\t}\n"
    "\n"
    "\tret = clk_prepare_enable(priv->clk);"
)
assert old_probe in src, "probe anchor not found"
src = src.replace(old_probe, new_probe, 1)

# 4. Assert reset in remove path
old_remove = (
    "\tpm_runtime_disable(&pdev->dev);\n"
    "\tci_hdrc_remove_device(priv->ci_pdev);\n"
    "\tclk_disable_unprepare(priv->clk);"
)
new_remove = (
    "\tpm_runtime_disable(&pdev->dev);\n"
    "\tci_hdrc_remove_device(priv->ci_pdev);\n"
    "\treset_control_assert(priv->rst);\n"
    "\tclk_disable_unprepare(priv->clk);"
)
assert old_remove in src, "remove anchor not found"
src = src.replace(old_remove, new_remove, 1)

open(path, "w").write(src)
print("patched OK")

with open("/tmp/ci_hdrc_usb2.c.orig") as f:
    orig = f.read()
diff = subprocess.run(
    ["diff", "-u", "/tmp/ci_hdrc_usb2.c.orig", path],
    capture_output=True,
    text=True,
)
# diff exits 1 when files differ, which is expected
out = diff.stdout
if not out.strip():
    raise SystemExit("diff produced no output — patch would be empty")

# Rewrite the diff header paths to a/ b/ form for patch -p1
lines = out.splitlines()
if lines and lines[0].startswith("--- "):
    lines[0] = "--- a/" + path
if len(lines) > 1 and lines[1].startswith("+++ "):
    lines[1] = "+++ b/" + path

with open(
    "/sdk/openwrt/build/patches/0099-usb-chipidea2-add-reset-handling.patch",
    "w",
) as f:
    f.write("\n".join(lines) + "\n")
print("patch written OK")
