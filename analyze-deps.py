#!/usr/bin/env python3
"""Inspect an authorized aTrust DEB without installing or executing its contents."""
import argparse
import collections
import datetime
import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile


def cmd(args, check=True):
    return subprocess.run(args, check=check, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, errors="replace")


def main():
    p = argparse.ArgumentParser(description="Offline/static aTrust DEB dependency inventory")
    p.add_argument("deb", help="Authorized local aTrustInstaller_amd64.deb")
    p.add_argument("--image", help="Optional local Docker runtime image to compare installed SONAMEs")
    p.add_argument("--out", default="runtime/data/atrust-dependencies.md")
    a = p.parse_args()
    for executable in ["dpkg-deb", "readelf"]:
        if not shutil.which(executable):
            p.error("Missing %s (apt install dpkg binutils)" % executable)
    deb = pathlib.Path(a.deb).expanduser().resolve(strict=True)
    if not deb.is_file():
        p.error("The DEB must be a regular file")
    fields = {}
    for key in ("Package", "Version", "Architecture", "Depends", "Pre-Depends", "Recommends"):
        fields[key] = cmd(["dpkg-deb", "-f", str(deb), key], check=False).stdout.strip()
    if fields["Architecture"] != "amd64" or "atrust" not in fields["Package"].lower():
        p.error("Not an AMD64 aTrust package: %r %r" % (fields["Package"], fields["Architecture"]))
    wanted = collections.defaultdict(list)
    bundled = set()
    objects = []
    count = 0
    with tempfile.TemporaryDirectory(prefix="atrust-deps-") as tmp:
        root = pathlib.Path(tmp) / "unpacked"
        root.mkdir()
        # dpkg-deb -x extracts package payload only; never executes preinst/postinst.
        cmd(["dpkg-deb", "-x", str(deb), str(root)])
        for directory, _, names in os.walk(root, followlinks=False):
            for name in names:
                path = pathlib.Path(directory) / name
                relative = "/" + str(path.relative_to(root))
                if ".so" in name:
                    bundled.add(name)
                if path.is_symlink():
                    continue
                with path.open("rb") as fp:
                    if fp.read(4) != b"\x7fELF":
                        continue
                count += 1
                dynamic = cmd(["readelf", "-W", "-d", str(path)], check=False).stdout
                needed = sorted(set(re.findall(r"\(NEEDED\).*?\[([^]]+)\]", dynamic)))
                sonames = re.findall(r"\(SONAME\).*?\[([^]]+)\]", dynamic)
                rpaths = re.findall(r"\((?:RPATH|RUNPATH)\).*?\[([^]]+)\]", dynamic)
                bundled.update(sonames)
                for lib in needed:
                    wanted[lib].append(relative)
                if needed or rpaths:
                    objects.append({"path": relative, "needed": needed, "rpaths": rpaths})
    provided = set(bundled)
    external = sorted(set(wanted) - provided)
    image_libs = set()
    image_error = ""
    if a.image:
        if not shutil.which("docker"):
            image_error = "Docker CLI not installed"
        else:
            # Check local availability before docker run: Docker otherwise pulls
            # non-existent "local/..." images from a remote registry.
            inspect = cmd(["docker", "image", "inspect", a.image], check=False)
            if inspect.returncode:
                image_error = ("Local image %s not found. Build it with ./build.sh "
                               "or omit --image for pure static analysis." % a.image)
            else:
                # Compare the image WITHOUT triggering a registry pull.
                # No aTrust client or external network is needed for this step.
                probe = cmd(["docker", "run", "--rm", "--pull=never",
                             "--network=none", "--entrypoint", "/bin/sh",
                             a.image, "-c", "ldconfig -p 2>/dev/null || true"],
                            check=False)
                if probe.returncode:
                    image_error = (probe.stderr or probe.stdout)[-400:]
                else:
                    image_libs = set(re.findall(
                        r"^\s*(\S+\.so(?:\.\S+)?)\s+\(",
                        probe.stdout, re.M))
    legacy = ("libssl.so.1.1", "libcrypto.so.1.1",
              "libldap-2.4.so", "libldap_r-2.4.so", "liblber-2.4.so",
              "libQt5Core.so", "libQt5Widgets.so", "libQt5Network.so")
    report = {
        "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "package": fields,
        "elf_files_scanned": count,
        "needed": {n: len(paths) for n, paths in sorted(wanted.items())},
        "bundled_libraries": sorted(bundled),
        "external_needed": external,
        "legacy_references": {
            name: paths for name, paths in sorted(wanted.items())
            if any(probe in name for probe in legacy)
        },
        "objects": objects,
        "image": a.image,
        "image_library_names": sorted(image_libs),
        "image_probe_error": image_error,
    }
    out = pathlib.Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    jsonfile = out.with_suffix(".json")
    jsonfile.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    lines = ["# aTrust static dependency analysis", "",
             "Generated: " + report["generated_at"], "",
             "## DEB metadata", "", "| Field | Value |", "|---|---|"]
    for field, value in fields.items():
        lines.append("| %s | %s |" % (field, (value or "(unspecified)").replace("|", "\\|")))
    lines += ["", "## ELF summary", "",
              "- ELF files: %s" % count,
              "- Unique DT_NEEDED: %s" % len(wanted),
              "- Libraries bundled in DEB (names and SONAMEs): %s" % len(bundled),
              "- External DT_NEEDED names: %s" % len(external), "",
              "## Legacy library references", "", "| Library pattern | Needed by ELF | Bundled in DEB | Present in image |",
              "|---|---|---|---|"]
    for pattern in legacy:
        refs = [name for name in wanted if pattern in name]
        owned = [name for name in bundled if pattern in name]
        present = [name for name in image_libs if pattern in name]
        lines.append("| %s | %s | %s | %s |" % (
            pattern, ", ".join(refs) or "No", ", ".join(owned) or "No",
            ", ".join(present) if a.image and not image_error else "Not checked"))
    lines += ["", "## Not bundled: externally needed shared libraries", "",
              "| DT_NEEDED | Referencing ELF files | In checked image |",
              "|---|---:|---|"]
    for name in external:
        img = ("Yes" if name in image_libs else "No") if a.image and not image_error else "Not checked"
        lines.append("| %s | %s | %s |" % (name, len(wanted[name]), img))
    lines += ["", "## Legacy reference paths", ""]
    for name, paths in report["legacy_references"].items():
        lines.append("### " + name)
        lines.extend("- " + path for path in paths)
        lines.append("")
    lines += ["## Limits", "",
              "- Static analysis only: installation scripts and packaged executables were NOT run.",
              "- DT_NEEDED does not include libraries resolved dynamically by dlopen, plugins, or invoked tools.",
              "- A matching SONAME does not guarantee ABI compatibility or correct library search ordering.",
              "- Package metadata and direct ELF links are different kinds of dependencies.",
              "- Analyze the exact DEB downloaded from the approved enterprise portal.", "",
              "Machine-readable detail: " + jsonfile.name]
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("Package: %s %s (%s)" % (fields["Package"], fields["Version"], fields["Architecture"]))
    print("ELF files: %d; external DT_NEEDED: %d" % (count, len(external)))
    print("Reports: %s and %s" % (out, jsonfile))
    if image_error:
        print("Image comparison unavailable: " + image_error)


if __name__ == "__main__":
    main()
