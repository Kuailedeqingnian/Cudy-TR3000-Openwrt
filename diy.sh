#!/bin/bash
set -e

echo "DIY script start..."

rm -rf package/custom/luci-theme-argon
rm -rf package/custom/luci-app-argon-config
mkdir -p package/custom

git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon.git package/custom/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config.git package/custom/luci-app-argon-config

sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate
sed -i 's/OpenWrt/TR3000-OpenWrt/g' package/base-files/files/bin/config_generate
sed -i 's#^root:[^:]*:#root::#' package/base-files/files/etc/shadow

find package feeds -iname '*picoclaw*' -exec rm -rf {} + || true

mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-default-argon <<'EOF'
#!/bin/sh
uci set luci.main.mediaurlbase='/luci-static/argon'
uci commit luci
exit 0
EOF
chmod +x files/etc/uci-defaults/99-default-argon

echo "Adding PassWall 26.4.15 fixed IPK files..."

mkdir -p passwall-ipk
mkdir -p files

if [ -f "PassWall-26.4.15-pack.zip" ]; then
  unzip -o PassWall-26.4.15-pack.zip -d passwall-ipk
fi

IPK_COUNT="$(find passwall-ipk -type f -name '*.ipk' | wc -l)"

if [ "$IPK_COUNT" -lt 6 ]; then
  echo "❌ PassWall IPK files not found or incomplete."
  echo "Please put 6 ipk files into passwall-ipk/ or upload PassWall-26.4.15-pack.zip"
  find passwall-ipk -type f || true
  exit 1
fi

extract_ipk() {
  PKG="$1"
  ABS_PKG="$(readlink -f "$PKG")"
  TMPDIR="$(mktemp -d)"

  echo "Extracting: $PKG"

  if ar t "$ABS_PKG" >/dev/null 2>&1; then
    echo "Format: ar ipk"
    (cd "$TMPDIR" && ar x "$ABS_PKG")
  elif tar -tf "$ABS_PKG" >/dev/null 2>&1; then
    echo "Format: tar-wrapped ipk"
    tar -xaf "$ABS_PKG" -C "$TMPDIR"
  else
    echo "❌ Unsupported ipk format: $PKG"
    file "$ABS_PKG" || true
    exit 1
  fi

  echo "Package inner files:"
  find "$TMPDIR" -maxdepth 3 -type f | sort || true

  DATA_FILE="$(find "$TMPDIR" -maxdepth 3 -type f -name 'data.tar*' | head -n 1)"

  if [ -z "$DATA_FILE" ]; then
    echo "❌ No data.tar found in $PKG"
    find "$TMPDIR" -maxdepth 5 -type f | sort || true
    exit 1
  fi

  echo "Extracting data archive: $DATA_FILE"
  tar -xaf "$DATA_FILE" -C files

  rm -rf "$TMPDIR"
}

for ipk in $(find passwall-ipk -type f -name '*.ipk' | sort); do
  extract_ipk "$ipk"
done

echo "Fixing executable permissions..."

find files -path '*/bin/*' -type f -exec chmod +x {} \; || true
find files -path '*/sbin/*' -type f -exec chmod +x {} \; || true
find files/etc/init.d -type f -exec chmod +x {} \; 2>/dev/null || true

echo "Checking injected PassWall files..."

find files -iname '*passwall*' | head -80 || true
find files -iname '*sing-box*' | head -30 || true
find files -iname '*xray*' | head -30 || true
find files -iname '*geoview*' | head -30 || true
find files -iname '*v2ray-plugin*' | head -30 || true

echo "Checking key files..."

if ! find files -iname '*passwall*' | grep -q passwall; then
  echo "❌ PassWall files not injected"
  exit 1
fi

if ! find files -iname '*sing-box*' | grep -q sing-box; then
  echo "❌ sing-box files not injected"
  exit 1
fi

if ! find files -iname '*xray*' | grep -q xray; then
  echo "❌ xray files not injected"
  exit 1
fi

if ! find files -iname '*geoview*' | grep -q geoview; then
  echo "❌ geoview files not injected"
  exit 1
fi

if ! find files -iname '*v2ray-plugin*' | grep -q v2ray-plugin; then
  echo "❌ v2ray-plugin files not injected"
  exit 1
fi

echo "✅ PassWall files injected successfully."

echo "PassWall 26.4.15 fixed IPK injection done."

echo "DIY script done."
