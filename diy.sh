#!/bin/bash

echo "DIY script start..."

# 修改默认IP
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

# 设置默认主题 Argon
sed -i "s/luci-theme-bootstrap/luci-theme-argon/g" feeds/luci/collections/luci/Makefile

# root 默认空密码
sed -i 's/root::0:0:99999:7:::/root:::0:99999:7:::/g' package/base-files/files/etc/shadow

# 删除 picoclaw（如果存在）
rm -rf package/*/picoclaw*
rm -rf feeds/*/picoclaw*

echo "DIY script done."
