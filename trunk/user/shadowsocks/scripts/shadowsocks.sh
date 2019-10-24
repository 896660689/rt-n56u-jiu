#!/bin/sh

ss_bin="ss-redir"
ss_json_file="/tmp/ss-redir.json"
ss_proc="/var/ss-redir"
Dnsmasq_dns="/etc/storage/dnsmasq/dnsmasq.conf"

while [ -n "`pidof ss-watchcat.sh`" ] ; do
	kill -9 "`pidof ss-watchcat.sh`"
	sleep 1
done

#/usr/bin/ss-redir -> /var/ss-redir -> /usr/bin/ss-orig-redir or /usr/bin/ssr-redir

ss_type="$(nvram get ss_type)" #0=ss;1=ssr

if [ "${ss_type:-0}" = "0" ]; then
	ln -sf /usr/bin/ss-orig-redir $ss_proc
elif [ "${ss_type:-0}" = "1" ]; then
	ss_protocol=$(nvram get ss_protocol)
	ss_proto_param=$(nvram get ss_proto_param)
	ss_obfs=$(nvram get ss_obfs)
	ss_obfs_param=$(nvram get ss_obfs_param)
	ln -sf /usr/bin/ssr-redir $ss_proc
fi

ss_local_port=$(nvram get ss_local_port)
ss_udp=$(nvram get ss_udp)
ss_server=$(nvram get ss_server)

ss_server_port=$(nvram get ss_server_port)
ss_method=$(nvram get ss_method)
ss_password=$(nvram get ss_key)
ss_mtu=$(nvram get ss_mtu)
ss_timeout=$(nvram get ss_timeout)

ss_mode=$(nvram get ss_mode) #0:global;1:chnroute;2:gfwlist
ss_router_proxy=$(nvram get ss_router_proxy)
ss_lower_port_only=$(nvram get ss_lower_port_only)

loger() {
	logger -st "$1" "$2"
}

get_arg_udp() {
	if [ "$ss_udp" = "1" ]; then
		echo "-u"
	fi
}

get_arg_out(){
	if [ "$ss_router_proxy" = "1" ]; then
		echo "-o"
	fi
}

get_wan_bp_list(){
	wanip="$(nvram get wan_ipaddr)"
	[ -n "$wanip" ] && [ "$wanip" != "0.0.0.0" ] && bp="-b $wanip" || bp=""
	if [ "$ss_mode" = "1" ]; then
		bp=${bp}" -B /etc/storage/chinadns/chnroute.txt"
	fi
	echo "$bp"
}

get_ip()
{
	IPADDR=$1
	regex="\b(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[1-9])\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[1-9])\b"
	ckStep2=`echo $1 | egrep $regex | wc -l`
	if [ $ckStep2 -eq 0 ];
	then
#		echo "The string $IPADDR is not a correct ipaddr!!!"
		ip=`ping -c 1 ${IPADDR} | grep '(' | cut -d '(' -f2|cut -d ')' -f1`
		if [ -z "${ip}" ]; then
			sleep 5
			ip=`ping -c 1 ${IPADDR} | grep '(' | cut -d '(' -f2|cut -d ')' -f1`
		fi
		echo ${ip}
	else
		echo $1
	fi
}

get_ipt_ext(){
	if [ "$ss_lower_port_only" = "1" ]; then
		echo '-e "--dport 22:1023"'
	elif [ "$ss_lower_port_only" = "2" ]; then
		echo '-e "-m multiport --dports 53,80,443"'
	fi
}

func_start_ss_redir(){
#	ipset create ss_spec_dst_sp hash:net hashsize 64
#	ipset add ss_spec_dst_sp $(get_ip `nvram get ss_server`)
	sh -c "$ss_bin -c $ss_json_file $(get_arg_udp) & "
	return $?
}

func_start_ss_rules(){
	ss-rules -f
	sh -c "ss-rules -s $ss_server -l $ss_local_port $(get_wan_bp_list) -d SS_SPEC_WAN_AC $(get_ipt_ext) $(get_arg_out) $(get_arg_udp)"
	return $?
}

func_gen_ss_json(){
cat > "$ss_json_file" <<EOF
{
    "server": "$ss_server",
    "server_port": $ss_server_port,
    "password": "$ss_password",
    "method": "$ss_method",
    "timeout": $ss_timeout,
    "protocol": "$ss_protocol",
    "protocol_param": "$ss_proto_param",
    "obfs": "$ss_obfs",
    "obfs_param": "$ss_obfs_param",
    "local_address": "0.0.0.0",
    "local_port": $ss_local_port,
    "mtu": $ss_mtu
}

EOF
}

func_start(){
	func_gen_ss_json && \
	func_start_ss_redir && \
	func_start_ss_rules && \
	restart_firewall && \
	loger $ss_bin "start done" || { ss-rules -f && loger $ss_bin "start fail!";}
	nohup /usr/bin/ss-watchcat.sh >> /tmp/ss-watchcat.log 2>&1 &
	grep "conf-dir" $Dnsmasq_dns
	if [ ! "$?" -eq "0" ]
	then
		sed -i '/min-cache/d; /conf-dir/d' $Dnsmasq_dns
		sed -i '$a min-cache-ttl=3600' $Dnsmasq_dns
		sed -i '$a conf-dir=/etc/storage/gfwlist' $Dnsmasq_dns
	fi
}

func_stop(){
	grep "conf-dir" $Dnsmasq_dns
	if [ "$?" -eq "0" ]
	then
		sed -i '/min-cache/d; /conf-dir/d' $Dnsmasq_dns
	fi
	if [ -n "`pidof ss-watchcat.sh`" ] ; then
		kill -9 "`pidof ss-watchcat.sh`"
	fi
	killall -q $ss_bin && restart_dhcpd
	ss-rules -f && loger $ss_bin "stop"
	[ -f /tmp/ss-redir.json ] && rm -rf /tmp/ss-redir.json
	[ -f /tmp/ss-watchcat.log ] && rm -rf /tmp/ss-watchcat.log
	[ -f /var/run/ss-watchdog.pid ] && rm -rf /var/run/ss-watchdog.pid
	[ -f /tmp/shadowsocks_iptables.save ] && rm -rf /tmp/shadowsocks_iptables.save
}

case "$1" in
start)
	func_start
	;;
stop)
	func_stop
	;;
restart)
	func_stop
	func_start
	;;
*)
	echo "Usage: $0 { start | stop | restart }"
	exit 1
	;;
esac