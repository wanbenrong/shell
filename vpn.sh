#!/bin/sh

CAMERA_ADDR=192.254.4.200
CAMERA_FLAG=0
VPN_ADDR=172.30.0.99
VPN_IFACE="ppp10"
VPN_NETMASK="192.168.2.0/24"
IPS_NAT="iptables -t nat"
XL2TPD_CFG="./xl2tpd/xl2tpd.conf"
XL2TPD_CFG_302="./xl2tpd/xl2tpd_302.conf"
MULTI_KO="./xl2tpd/xt_multiport.ko"
LOG="logger -t $(basename "$0")[$$] -p"
PORTS="--dports 80,443,554,8000,8443,7681,7682"
HWP=""

destroy_rules() {
	ip route del $VPN_NETMASK dev ppp10
	#摄像头策略路由
	ip rule del from $CAMERA_ADDR table 10 
	ip route del default via $VPN_ADDR dev ppp10 table 10
	#vpn端口net规则
	 $IPS_NAT -D POSTROUTING -o ppp10  -j MASQUERADE
	#映射规则
	$IPS_NAT -D PREROUTING -i ppp10 -p tcp -m multiport $PORTS -j DNAT --to-destination $CAMERA_ADDR
	$IPS_NAT -D PREROUTING -i ppp10 -p udp -m multiport $PORTS -j DNAT --to-destination $CAMERA_ADDR
}

add_rules() {
	ip route add 10.60.0.0/16 dev ppp10
	ip route add $VPN_NETMASK dev ppp10
	#摄像头策略路由
	ip rule add from $CAMERA_ADDR table 10 
	ip route add default via $VPN_ADDR dev ppp10 table 10
	#vpn端口net规则
	 $IPS_NAT -I POSTROUTING -o ppp10  -j MASQUERADE
	#映射规则
	$IPS_NAT -I PREROUTING -i ppp10 -p tcp -m multiport $PORTS -j DNAT --to-destination $CAMERA_ADDR
	$IPS_NAT -I PREROUTING -i ppp10 -p udp -m multiport $PORTS -j DNAT --to-destination $CAMERA_ADDR
}

vpn_restart() {
	local table_10=`ip route show table 10`
	
	$LOG info "\"${HWP}\"vpn_restart start"
	killall -9 xl2tpd
	killall -9 echo
	if [ $HWP == "TA302" -o $HWP == "TA332" ]; then
		xl2tpd -c $XL2TPD_CFG_302
	else
		/dw/ver_main/bin/xl2tpd -c $XL2TPD_CFG
	fi
	sleep 2
	echo "c gw_vpn" > /var/run/xl2tpd/l2tp-control &
	sleep 10	
	ip route add default via $VPN_ADDR dev ppp10 table 10
	ip route add 10.60.0.0/16 dev ppp10
	$LOG info "vpn_restart end"	
}


main() {
	local camera_exist=0
	local vpn_iface=0
	local add_rule_flag=0
	
	
	HWP=`factory_env get BOOT_HWP | cut -d "=" -f 2`
	destroy_rules
	
	if [ $HWP == "TA302" -o $HWP == "TA332" ]; then
		rmmod xt_multiport
		insmod $MULTI_KO  
	fi
	while true; do
		#检测摄像头
		ping -c 1 -s 10 -q $CAMERA_ADDR &> /dev/null		
		if [ $? -eq 0 ]; then
			camera_exist=1
		else
			camera_exist=0
		fi
		
		ifconfig $VPN_IFACE &> /dev/null
		if [ $? -eq 0 ]; then
			vpn_iface=1
		else
			vpn_iface=0
		fi				
		$LOG info "camera_exist:\"${camera_exist}\" vpn_iface:\"${vpn_iface}\""
		if [ $camera_exist -eq 1 -a $vpn_iface -eq 0 ]; then
			vpn_restart
		fi

		ping -c 1 -s 10 -q $VPN_ADDR &> /dev/null
		if [ $? -eq 0 ]; then
			$LOG info "vpn connect success!"
			if [ $add_rule_flag -eq 0 ]; then
				add_rules
				add_rule_flag=1
			fi
		else
			$LOG info "vpn connect fail!!!"
		fi
		sleep 10
	done
}

main "$@"
