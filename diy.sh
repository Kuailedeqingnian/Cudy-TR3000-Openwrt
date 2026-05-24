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
  TMPDIR="$(mktemp -d)"

  echo "Extracting: $PKG"

  if ar t "$PKG" >/dev/null 2>&1; then
    (cd "$TMPDIR" && ar x "$OLDPWD/$PKG")
    DATA_FILE="$(find "$TMPDIR" -maxdepth 1 -name 'data.tar*' | head -n 1)"

    if [ -z "$DATA_FILE" ]; then
      echo "❌ No data.tar found in $PKG"
      exit 1
    fi

    tar -xaf "$DATA_FILE" -C files

  elif tar -tf "$PKG" >/dev/null 2>&1; then
    tar -xaf "$PKG" -C files

  else
    echo "❌ Unsupported ipk format: $PKG"
    exit 1
  fi

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

find files -iname '*passwall*' | head -50 || true
find files -iname '*sing-box*' | head -20 || true
find files -iname '*xray*' | head -20 || true
find files -iname '*geoview*' | head -20 || true
find files -iname '*v2ray-plugin*' | head -20 || true

echo "PassWall 26.4.15 fixed IPK injection done."

echo "DIY script done."
