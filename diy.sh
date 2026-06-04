#!/bin/bash
set -e

echo "DIY script start..."

rm -rf package/custom/luci-theme-argon
rm -rf package/custom/luci-app-argon-config
mkdir -p package/custom

git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon.git package/custom/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config.git package/custom/luci-app-argon-config

sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate
sed -i 's/OpenWrt/Cudy-TR3000-OpenWrt/g' package/base-files/files/bin/config_generate
sed -i 's#^root:[^:]*:#root::#' package/base-files/files/etc/shadow

find package feeds -iname '*picoclaw*' -exec rm -rf {} + || true

mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-default-argon <<'EOF'
#!/bin/sh
uci set luci.main.mediaurlbase='/luci-static/argon'
uci set luci.main.lang='zh_cn'
uci commit luci
exit 0
EOF
chmod +x files/etc/uci-defaults/99-default-argon

echo "Adding TR3000 status info..."

mkdir -p files/etc/profile.d
mkdir -p package/base-files/files/etc/profile.d

cat > package/base-files/files/etc/profile.d/tr3000-info.sh <<'EOF'
#!/bin/sh

CPU_FREQ="Unknown"

for f in \
/sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq \
/sys/devices/system/cpu/cpufreq/policy0/cpuinfo_cur_freq
do
    if [ -f "$f" ]; then
        CPU_FREQ="$(expr $(cat "$f") / 1000) MHz"
        break
    fi
done

ONLINE_DEVICES=$(awk 'NF >=4 {print $2}' /tmp/dhcp.leases 2>/dev/null | sort -u | wc -l)

echo ""
echo "========== TR3000 System Info =========="
echo "CPU Frequency : $CPU_FREQ"
echo "Online Devices: $ONLINE_DEVICES"
echo "========================================"
echo ""

EOF

chmod +x package/base-files/files/etc/profile.d/tr3000-info.sh
cp package/base-files/files/etc/profile.d/tr3000-info.sh files/etc/profile.d/tr3000-info.sh
chmod +x files/etc/profile.d/tr3000-info.sh

echo "TR3000 status file check:"
ls -l files/etc/profile.d/tr3000-info.sh
ls -l package/base-files/files/etc/profile.d/tr3000-info.sh

echo "DIY script done."
