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

echo "Adding TR3000 temperature display patch..."

mkdir -p files/sbin
mkdir -p files/usr/share/rpcd/acl.d
mkdir -p files/www/luci-static/resources/view/status/include

cat > files/sbin/tempinfo <<'EOF'
#!/bin/sh

. /etc/openwrt_release

IEEE_PATH="/sys/class/ieee80211"
THERMAL_PATH="/sys/class/thermal"

case "$DISTRIB_TARGET" in
ipq40xx/*|ipq806x/*)
	wifi_temp="$(awk '{printf("%.1f°C ", $0 / 1000)}' "$IEEE_PATH"/phy*/device/hwmon/hwmon*/temp1_input 2>/dev/null | awk '$1=$1')"
	;;
mediatek/mt7622)
	wifi_temp="$(awk '{printf("%.1f°C ", $0 / 1000)}' "$IEEE_PATH"/wl*/hwmon*/temp1_input 2>/dev/null | awk '$1=$1')"
	;;
*)
	wifi_temp="$(awk '{printf("%.1f°C ", $0 / 1000)}' "$IEEE_PATH"/phy*/hwmon*/temp1_input 2>/dev/null | awk '$1=$1')"
	;;
esac

cpu_temp="$(awk '{printf("%.1f°C", $0 / 1000)}' "$THERMAL_PATH/thermal_zone0/temp" 2>/dev/null)"

if [ -n "$cpu_temp" ] && [ -z "$wifi_temp" ]; then
	echo -n "CPU: $cpu_temp"
elif [ -z "$cpu_temp" ] && [ -n "$wifi_temp" ]; then
	echo -n "WiFi: $wifi_temp"
elif [ -n "$cpu_temp" ] && [ -n "$wifi_temp" ]; then
	echo -n "CPU: $cpu_temp, WiFi: $wifi_temp"
else
	echo -n "No temperature info"
fi
EOF

cat > files/sbin/cpuinfo <<'EOF'
#!/bin/sh

cpu_arch="$(grep 'model name' /proc/cpuinfo | sed -n '1p' | awk -F ': ' '{print $2}')"
[ -z "${cpu_arch}" ] && cpu_arch="ARMv8 Processor"

cpu_cores="$(grep -c '^processor' /proc/cpuinfo)"

if grep -q "filogic" /etc/openwrt_release; then
	if [ -f "/sys/devices/system/cpu/cpufreq/policy0/cpuinfo_cur_freq" ]; then
		cpu_freq="$(expr $(cat /sys/devices/system/cpu/cpufreq/policy0/cpuinfo_cur_freq) / 1000)MHz"
	fi
fi

cpu_temp="$(awk "BEGIN{printf (\"%.1f\",$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)/1000) }" 2>/dev/null)°C"

if [ -n "$cpu_freq" ]; then
	echo -n "${cpu_arch} x ${cpu_cores} (${cpu_freq}, ${cpu_temp})"
else
	echo -n "${cpu_arch} x ${cpu_cores} (${cpu_temp})"
fi
EOF

chmod +x files/sbin/tempinfo
chmod +x files/sbin/cpuinfo

cat > files/usr/share/rpcd/acl.d/luci-mod-status-autocore.json <<'EOF'
{
	"luci-mod-status-autocore": {
		"description": "Grant access to temperature and cpu info",
		"read": {
			"ubus": {
				"luci": [ "getCPUInfo", "getCPUUsage", "getTempInfo" ]
			}
		}
	}
}
EOF

cat > files/www/luci-static/resources/view/status/include/10_system.js <<'EOF'
'use strict';
'require baseclass';
'require rpc';

var callLuciVersion = rpc.declare({
	object: 'luci',
	method: 'getVersion'
});

var callSystemBoard = rpc.declare({
	object: 'system',
	method: 'board'
});

var callSystemInfo = rpc.declare({
	object: 'system',
	method: 'info'
});

var callCPUInfo = rpc.declare({
	object: 'luci',
	method: 'getCPUInfo'
});

var callCPUUsage = rpc.declare({
	object: 'luci',
	method: 'getCPUUsage'
});

var callTempInfo = rpc.declare({
	object: 'luci',
	method: 'getTempInfo'
});

return baseclass.extend({
	title: _('System'),

	load: function() {
		return Promise.all([
			L.resolveDefault(callSystemBoard(), {}),
			L.resolveDefault(callSystemInfo(), {}),
			L.resolveDefault(callCPUInfo(), {}),
			L.resolveDefault(callCPUUsage(), {}),
			L.resolveDefault(callTempInfo(), {}),
			L.resolveDefault(callLuciVersion(), { revision: _('unknown version'), branch: 'LuCI' })
		]);
	},

	render: function(data) {
		var boardinfo   = data[0],
		    systeminfo  = data[1],
		    cpuinfo     = data[2],
		    cpuusage    = data[3],
		    tempinfo    = data[4],
		    luciversion = data[5];

		luciversion = luciversion.branch + ' ' + luciversion.revision;

		var datestr = null;

		if (systeminfo.localtime) {
			var date = new Date(systeminfo.localtime * 1000);

			datestr = '%04d-%02d-%02d %02d:%02d:%02d'.format(
				date.getUTCFullYear(),
				date.getUTCMonth() + 1,
				date.getUTCDate(),
				date.getUTCHours(),
				date.getUTCMinutes(),
				date.getUTCSeconds()
			);
		}

		var fields = [
			_('Hostname'),         boardinfo.hostname,
			_('Model'),            boardinfo.model,
			_('Architecture'),     cpuinfo.cpuinfo || boardinfo.system,
			_('Target Platform'),  (L.isObject(boardinfo.release) ? boardinfo.release.target : ''),
			_('Firmware Version'), (L.isObject(boardinfo.release) ? boardinfo.release.description + ' / ' : '') + (luciversion || ''),
			_('Kernel Version'),   boardinfo.kernel,
			_('Local Time'),       datestr,
			_('Uptime'),           systeminfo.uptime ? '%t'.format(systeminfo.uptime) : null,
			_('Load Average'),     Array.isArray(systeminfo.load) ? '%.2f, %.2f, %.2f'.format(
				systeminfo.load[0] / 65535.0,
				systeminfo.load[1] / 65535.0,
				systeminfo.load[2] / 65535.0
			) : null,
			_('CPU usage (%)'),    cpuusage.cpuusage
		];

		if (tempinfo.tempinfo) {
			fields.splice(6, 0, _('Temperature'));
			fields.splice(7, 0, tempinfo.tempinfo);
		}

		var table = E('table', { 'class': 'table' });

		for (var i = 0; i < fields.length; i += 2) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, [ fields[i] ]),
				E('td', { 'class': 'td left' }, [ (fields[i + 1] != null) ? fields[i + 1] : '?' ])
			]));
		}

		return table;
	}
});
EOF

RPC_FILE=""
if [ -f "feeds/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci" ]; then
	RPC_FILE="feeds/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci"
elif [ -f "package/feeds/luci/luci-base/root/usr/share/rpcd/ucode/luci" ]; then
	RPC_FILE="package/feeds/luci/luci-base/root/usr/share/rpcd/ucode/luci"
fi

if [ -n "$RPC_FILE" ]; then
	echo "Patching rpcd luci ucode: $RPC_FILE"

	python3 - <<'PY'
from pathlib import Path

candidates = [
    Path("feeds/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci"),
    Path("package/feeds/luci/luci-base/root/usr/share/rpcd/ucode/luci"),
]

rpc_file = next((p for p in candidates if p.exists()), None)
if rpc_file is None:
    raise SystemExit("rpcd luci ucode file not found")

s = rpc_file.read_text()

if "getTempInfo:" not in s:
    block = r'''
	getCPUInfo: {
		call: function() {
			if (!access('/sbin/cpuinfo'))
				return {};

			const fd = popen('/sbin/cpuinfo');
			if (fd) {
				let cpuinfo = fd.read('all');
				if (!cpuinfo)
					cpuinfo = '?';
				fd.close();

				return { cpuinfo: cpuinfo };
			} else {
				return { cpuinfo: error() };
			}
		}
	},

	getCPUUsage: {
		call: function() {
			const fd = popen('top -n1 | awk \'/^CPU/ {printf("%d%", 100 - $8)}\'');
			let cpuusage = fd.read('all');
			if (!cpuusage)
				cpuusage = '?';
			fd.close();

			return { cpuusage: cpuusage };
		}
	},

	getTempInfo: {
		call: function() {
			if (!access('/sbin/tempinfo'))
				return {};

			const fd = popen('/sbin/tempinfo');
			if (fd) {
				let tempinfo = fd.read('all');
				if (!tempinfo)
					tempinfo = '?';
				fd.close();

				return { tempinfo: tempinfo };
			} else {
				return { tempinfo: error() };
			}
		}
	},

'''
    marker = "\n\tgetOnlineUsers: {"
    if marker in s:
        s = s.replace(marker, "\n" + block + "\tgetOnlineUsers: {", 1)
    else:
        marker = "\n\tgetRealtimeStats: {"
        if marker in s:
            s = s.replace(marker, "\n" + block + "\tgetRealtimeStats: {", 1)
        else:
            raise SystemExit("Unable to find insertion marker in rpcd luci ucode")

    rpc_file.write_text(s)
    print("rpcd luci ucode patched")
else:
    print("getTempInfo already exists, skip patch")
PY
else
	echo "Warning: rpcd luci ucode file not found, skip rpc patch"
fi

echo "TR3000 temperature display patch done."

echo "DIY script done."
