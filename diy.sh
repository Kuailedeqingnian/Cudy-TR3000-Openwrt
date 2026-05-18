#!/bin/bash
set -e

echo "DIY script start..."

# 默认 IP 改为 192.168.2.1
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

# 默认主机名
sed -i 's/OpenWrt/TR3000-OpenWrt/g' package/base-files/files/bin/config_generate

# 默认主题改为 Argon
if [ -f feeds/luci/collections/luci/Makefile ]; then
  sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
fi

# root 默认空密码
sed -i 's#^root:[^:]*:#root::#' package/base-files/files/etc/shadow

# 删除 picoclaw 相关内容
find package feeds -iname '*picoclaw*' -exec rm -rf {} + || true

echo "DIY script done."
