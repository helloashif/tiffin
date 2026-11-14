#!/bin/sh
# Installs Tiffin on macOS and Linux from the latest GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/scripts/install.sh | sh
#
# Environment:
#   TIFFIN_VERSION  install this release (x.y.z, no v) instead of the latest
#   TIFFIN_REPO     owner/name of the release repository (default helloashif/tiffin)
#   TIFFIN_CLI_ONLY=1  install only the command line programs, in ~/.local/bin
#
# macOS: the signed dmg; Tiffin.app goes to /Applications.
# Linux: the .deb (apt) or .rpm (dnf/zypper); any other distribution gets the
#        command line programs from the tar.gz.
# Every download is checked against the release's checksums.txt.
# Windows: use scripts/install.ps1.
set -eu

REPO=${TIFFIN_REPO:-helloashif/tiffin}
BASE=https://github.com/$REPO/releases

say() { printf '%s\n' "$*"; }
die() { printf 'install: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required"; }

need curl
need tar

# --- what are we on -------------------------------------------------------
case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *) die "unsupported system $(uname -s); on Windows run scripts/install.ps1" ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=amd64; rpmarch=x86_64 ;;
  aarch64 | arm64) arch=arm64; rpmarch=aarch64 ;;
  *) die "unsupported architecture $(uname -m)" ;;
esac

# --- which release --------------------------------------------------------
version=${TIFFIN_VERSION:-}
if [ -z "$version" ]; then
  url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$BASE/latest") || die "cannot reach $BASE/latest"
  version=${url##*/}
fi
version=${version#v}
case "$version" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) die "no release found at $BASE (got '$version')" ;;
esac
say "Installing Tiffin $version ($os/$arch)"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

fetch() { # fetch FILE: download a release asset into $tmp and check it
  curl -fSL --progress-bar -o "$tmp/$1" "$BASE/download/v$version/$1" || die "download of $1 failed"
  want=$(grep " \*\{0,1\}$1\$" "$tmp/checksums.txt" | awk '{print $1}')
  [ -n "$want" ] || die "$1 is not in checksums.txt"
  if command -v sha256sum >/dev/null 2>&1; then
    got=$(sha256sum "$tmp/$1" | awk '{print $1}')
  else
    got=$(shasum -a 256 "$tmp/$1" | awk '{print $1}')
  fi
  [ "$want" = "$got" ] || die "checksum mismatch for $1"
}
curl -fsSL -o "$tmp/checksums.txt" "$BASE/download/v$version/checksums.txt" || die "no checksums.txt for $version"

sudo_cmd=
if [ "$(id -u)" != 0 ]; then
  command -v sudo >/dev/null 2>&1 || die "run as root, or install sudo"
  sudo_cmd=sudo
fi

install_cli() { # tarball of the programs into ~/.local/bin
  f=tiffin_${version}_${os}_${arch}.tar.gz
  fetch "$f"
  mkdir -p "$tmp/cli" "$HOME/.local/bin"
  tar -xzf "$tmp/$f" -C "$tmp/cli"
  for p in tiffin tiffind tiffin-helper tiffin-shim; do
    [ -f "$tmp/cli/$p" ] || die "$p is missing from $f"
    install -m 0755 "$tmp/cli/$p" "$HOME/.local/bin/$p"
  done
  say "Installed the command line programs in ~/.local/bin"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) say "Add ~/.local/bin to your PATH:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
  esac
}

# --- install --------------------------------------------------------------
if [ "${TIFFIN_CLI_ONLY:-}" = 1 ]; then
  install_cli
elif [ "$os" = darwin ]; then
  need hdiutil
  f=Tiffin-$version.dmg
  fetch "$f"
  mnt=$tmp/mnt
  mkdir -p "$mnt"
  hdiutil attach -nobrowse -quiet -readonly -mountpoint "$mnt" "$tmp/$f" || die "cannot open $f"
  dest=/Applications
  [ -w "$dest" ] || { dest=$HOME/Applications; mkdir -p "$dest"; }
  rm -rf "$dest/Tiffin.app"
  cp -R "$mnt/Tiffin.app" "$dest/" || { hdiutil detach -quiet "$mnt" || true; die "copy to $dest failed"; }
  hdiutil detach -quiet "$mnt" || true
  mkdir -p "$HOME/.local/bin"
  ln -sf "$dest/Tiffin.app/Contents/MacOS/tiffin" "$HOME/.local/bin/tiffin"
  say "Installed $dest/Tiffin.app and linked tiffin into ~/.local/bin"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) say "Add ~/.local/bin to your PATH:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
  esac
else
  deb=$(printf '%s' "$version" | sed 's/-/~/')
  if command -v apt-get >/dev/null 2>&1; then
    f=tiffin_${deb}_${arch}.deb
    fetch "$f"
    $sudo_cmd apt-get install -y "$tmp/$f"
  elif command -v dnf >/dev/null 2>&1; then
    f=tiffin-${deb}-1.${rpmarch}.rpm
    fetch "$f"
    $sudo_cmd dnf install -y "$tmp/$f"
  elif command -v zypper >/dev/null 2>&1; then
    f=tiffin-${deb}-1.${rpmarch}.rpm
    fetch "$f"
    $sudo_cmd zypper --non-interactive --no-gpg-checks install "$tmp/$f"
  else
    say "No apt, dnf or zypper found: installing the command line programs only."
    install_cli
  fi
fi

say ""
say "Done. Next:"
say "  tiffin elevate    # one-time system setup (asks for your password)"
say "  tiffin doctor     # check everything works"
