#!/usr/bin/env bash
# NovaOS one-shot setup + build. Usage: bash build.sh
# Run it in the folder that contains novaos-part1.zip (or the novaos folder).
set -u

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

START="$(pwd)"

say "Locating project"
if [ -f Makefile ] && [ -f linker.ld ]; then
  PROJ="$START"
elif [ -f novaos/Makefile ]; then
  PROJ="$START/novaos"
else
  ZIP="$(ls -1 "$START"/novaos-part1.zip ~/novaos-part1.zip /workspaces/*/novaos-part1.zip 2>/dev/null | head -n1)"
  [ -n "${ZIP:-}" ] || die "novaos-part1.zip not found. Upload it next to build.sh."
  say "Unzipping $ZIP"
  (cd "$(dirname "$ZIP")" && unzip -oq "$ZIP") || die "unzip failed"
  PROJ="$(dirname "$ZIP")/novaos"
fi
cd "$PROJ" || die "cannot enter $PROJ"
echo "Project: $PROJ"

say "Repairing layout if files are misplaced"
mkdir -p kernel/include kernel/src
# Fix the case where files landed in the project root or in a literal '{include,src}' dir
for d in . 'kernel/{include,src}'; do
  [ -d "$d" ] || continue
  for f in "$d"/*.h;   do [ -f "$f" ] && mv -f "$f" kernel/include/; done
  for f in "$d"/*.c "$d"/*.asm; do [ -f "$f" ] && mv -f "$f" kernel/src/; done
done
rm -rf 'kernel/{include,src}'

say "Installing tools (nasm, xorriso, git, gcc, make, qemu)"
if command -v apt-get >/dev/null 2>&1; then
  SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
  $SUDO apt-get update -qq || echo "apt update had warnings, continuing"
  $SUDO apt-get install -y -qq nasm xorriso git build-essential make curl qemu-system-x86 \
    || die "apt install failed"
else
  die "No apt-get found. On macOS: brew install nasm xorriso qemu git x86_64-elf-gcc"
fi

for t in gcc ld nasm xorriso git make; do
  command -v "$t" >/dev/null 2>&1 || die "'$t' still missing after install"
done

# Use host gcc unless a real cross compiler exists
if command -v x86_64-elf-gcc >/dev/null 2>&1; then PFX="x86_64-elf-"; else PFX=""; fi

say "Cleaning"
make clean >/dev/null 2>&1
rm -rf limine kernel/include/limine.h   # force a fresh Limine fetch

say "Building ISO (this clones Limine, so it needs internet)"
make ARCH_PREFIX="$PFX" iso || die "build failed - copy the FIRST 'error' line above and send it to Claude"

[ -f novaos.iso ] || die "novaos.iso was not produced"
echo; ls -lh novaos.iso

say "Boot test (headless, 15s)"
rm -f serial.log
timeout 15 qemu-system-x86_64 -M q35 -m 256M -cdrom novaos.iso \
  -display none -serial file:serial.log -no-reboot >/dev/null 2>&1
echo "----- serial.log -----"; cat serial.log 2>/dev/null; echo "----------------------"
if grep -q "Milestone 1" serial.log 2>/dev/null; then
  say "SUCCESS: NovaOS booted."
else
  echo "Boot output above is incomplete. Send serial.log contents to Claude."
fi
echo; echo "ISO: $PROJ/novaos.iso  (long-press it in the file list -> Download)"
