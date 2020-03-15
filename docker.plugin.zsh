#!/bin/bash

#Bash wrappers for docker run commands

export DOCKER_REPO_PREFIX=jess

alias d="docker"
alias db='docker build'
alias de='docker exec'
alias di='docker images'
alias dip='docker inspect --format "{{ .NetworkSettings.IPAddress }}" $*'
alias dlog='docker logs'
alias dps='docker ps'
alias dpsl='docker ps -l $*'
alias drm='docker rm'
alias drmi='docker rmi'
alias drmia='docker rmi $* $(docker images -a -q)'
alias drmid='docker rmi $* $(docker images -q -f "dangling=true")'
alias drms='docker rm $* $(docker ps -q -f "status=exited")'
alias drmvs='docker rm -v $* $(docker ps -q -f "status=exited")'
alias drma='docker rm $* $(docker ps -a -q)'
alias drmva='docker rm -v $* $(docker ps -a -q)'
alias dsa='docker stop $* $(docker ps -q -f "status=running")'
alias dvls='docker volume ls $*'
alias dvrma='docker volume rm $(docker volume ls -q)'
alias dvrmd='docker volume rm $(docker volume ls -q -f "dangling=true")'

#
# Helper Functions
#
dcleanup(){
	local containers
	mapfile -t containers < <(docker ps -aq 2>/dev/null)
	docker rm "${containers[@]}" 2>/dev/null
	local volumes
	mapfile -t volumes < <(docker ps --filter status=exited -q 2>/dev/null)
	docker rm --volume "${volumes[@]}" 2>/dev/null
	local images
	mapfile -t images < <(docker images --filter dangling=true -q 2>/dev/null)
	docker rmi "${images[@]}" 2>/dev/null
}

del_stopped(){
	local name=$1
	local state
	state=$(docker inspect --format "{{.State.Running}}" "$name" 2>/dev/null)

	if [[ "$state" == "false" ]]; then
		docker rm "$name"
	fi
}

rmctr(){
	# shellcheck disable=SC2068
	docker rm -f $@ 2>/dev/null || true
}

relies_on(){
	for container in "$@"; do
		local state
		state=$(docker inspect --format "{{.State.Running}}" "$container" 2>/dev/null)

		if [[ "$state" == "false" ]] || [[ "$state" == "" ]]; then
			echo "$container is not running, starting it for you."
			$container
		fi
	done
}

# creates an nginx config for a local route
nginx_config(){
	server=$1
	route=$2

	cat >"${HOME}/.nginx/conf.d/${server}.conf" <<-EOF
	upstream ${server} { server ${route}; }
	server {
	server_name ${server};

	location / {
	proxy_pass  http://${server};
	proxy_http_version 1.1;
	proxy_set_header Upgrade \$http_upgrade;
	proxy_set_header Connection "upgrade";
	proxy_set_header Host \$http_host;
	proxy_set_header X-Forwarded-Proto \$scheme;
	proxy_set_header X-Forwarded-For \$remote_addr;
	proxy_set_header X-Forwarded-Port \$server_port;
	proxy_set_header X-Request-Start \$msec;
}
	}
	EOF

	# restart nginx
	docker restart nginx

	# add host to /etc/hosts
	hostess add "$server" 127.0.0.1

	# open browser
	browser-exec "http://${server}"
}

#
# Container Aliases
#
apt_file(){
	docker run --rm -it \
		--name apt-file \
		${DOCKER_REPO_PREFIX}/apt-file
}
alias apt-file="apt_file"
daudacity(){
	del_stopped audacity

	docker run -d \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		--env "DISPLAY=unix${DISPLAY}" \
		--env QT_DEVICE_PIXEL_RATIO \
		--device /dev/snd \
		--group-add audio \
		--name audacity \
		${DOCKER_REPO_PREFIX}/audacity
}

daws(){
	docker run -it --rm \
		--name aws \
		--log-driver none \
		--volume "${HOME}/.aws:/root/.aws" \
		${DOCKER_REPO_PREFIX}/awscli "$@"
}

daz(){
	docker run -it --rm \
		--log-driver none \
		--volume "${HOME}/.azure:/root/.azure" \
		${DOCKER_REPO_PREFIX}/azure-cli "$@"
}

dbees(){
	docker run -it --rm \
		--env NOTARY_TOKEN \
		--log-driver none \
		--name bees \
		--volume "${HOME}/.bees:/root/.bees" \
		--volume "${HOME}/.boto:/root/.boto" \
		--volume "${HOME}/.dev:/root/.ssh:ro" \
		${DOCKER_REPO_PREFIX}/beeswithmachineguns "$@"
}

dcadvisor(){
	docker run -d \
		--name cadvisor \
		--publish 1234:8080 \
		--restart always \
		--volume /:/rootfs:ro \
		--volume /var/run:/var/run:rw \
		--volume /sys:/sys:ro  \
		--volume /var/lib/docker/:/var/lib/docker:ro \
		google/cadvisor

	hostess add cadvisor "$(docker inspect --format '{{.NetworkSettings.Networks.bridge.IPAddress}}' cadvisor)"
	browser-exec "http://cadvisor:8080"
}

dcheese(){
	del_stopped cheese

	docker run -d \
		--device /dev/video0 \
		--device /dev/snd \
		--device /dev/dri \
		--env "DISPLAY=unix${DISPLAY}" \
		--name cheese \
		--volume "${HOME}/Pictures:/root/Pictures" \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		${DOCKER_REPO_PREFIX}/cheese
}

dchrome(){
	# add flags for proxy if passed
	local proxy=
	local map
	local args=$*
	if [[ "$1" == "tor" ]]; then
		relies_on torproxy

		map="MAP * ~NOTFOUND , EXCLUDE torproxy"
		proxy="socks5://torproxy:9050"
		args="https://check.torproject.org/api/ip ${*:2}"
	fi

	del_stopped chrome

	# one day remove /etc/hosts bind mount when effing
	# overlay support inotify, such bullshit
	docker run -d \
		--device /dev/snd \
		--device /dev/dri \
		--device /dev/video0 \
		--device /dev/usb \
		--device /dev/bus/usb \
		--env "DISPLAY=unix${DISPLAY}" \
		--group-add audio \
		--group-add video \
		--memory 3gb \
		--name chrome \
		--security-opt seccomp:/etc/docker/seccomp/chrome.json \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		--volume "${HOME}/Downloads:/root/Downloads" \
		--volume "${HOME}/Pictures:/root/Pictures" \
		--volume "${HOME}/Torrents:/root/Torrents" \
		--volume "${HOME}/.chrome:/data" \
		--volume /dev/shm:/dev/shm \
		--volume /etc/hosts:/etc/hosts \
		${DOCKER_REPO_PREFIX}/chrome \
		--user-data-dir=/data \
		--proxy-server="$proxy" \
		--host-resolver-rules="$map" "$args"

}

dconsul(){
	del_stopped consul

	# check if we passed args and if consul is running
	local state
	state=$(docker inspect --format "{{.State.Running}}" consul 2>/dev/null)
	if [[ "$state" == "true" ]] && [[ "$*" != "" ]]; then
		docker exec -it consul consul "$@"
		return 0
	fi

	docker run -d \
		--env GOMAXPROCS=2 \
		--name consul \
		--net host \
		--restart always \
		--volume "${HOME}/.consul:/etc/consul.d" \
		--volume /var/run/docker.sock:/var/run/docker.sock \
		${DOCKER_REPO_PREFIX}/consul \
		agent \
		-bootstrap-expect 1 \
		-config-dir /etc/consul.d \
		-data-dir /data \
		-encrypt "$(docker run --rm ${DOCKER_REPO_PREFIX}/consul keygen)" \
		-ui-dir /usr/src/consul \
		-server \
		-dc neverland \
		-bind 0.0.0.0

	hostess add consul "$(docker inspect --format '{{.NetworkSettings.Networks.bridge.IPAddress}}' consul)"
	browser-exec "http://consul:8500"
}

dcura(){
	del_stopped cura

	docker run -d \
		--device /dev/dri \
		--env "DISPLAY=unix${DISPLAY}" \
		--env QT_DEVICE_PIXEL_RATIO \
		--env GDK_SCALE \
		--env GDK_DPI_SCALE \
		--name cura \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		--volume "${HOME}/cura:/root/cura" \
		--volume "${HOME}/.cache/cura:/root/.cache/cura" \
		--volume "${HOME}/.config/cura:/root/.config/cura" \
		${DOCKER_REPO_PREFIX}/cura
}

dcos(){
	docker run -it --rm \
		--volume "${HOME}/.dcos:/root/.dcos" \
		--volume "$(pwd):/root/apps" \
		--workdir /root/apps \
		${DOCKER_REPO_PREFIX}/dcos-cli "$@"
}

dfigma() {
	del_stopped figma

	docker run --rm -it \
		--env "DISPLAY=unix${DISPLAY}" \
		--name figma \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		${DOCKER_REPO_PREFIX}/figma-wine bash
}

dfirefox(){
	del_stopped firefox

	docker run -d \
		--cpuset-cpus 0 \
		--device /dev/snd \
		--device /dev/dri \
		--env "DISPLAY=unix${DISPLAY}" \
		--env GDK_SCALE \
		--env GDK_DPI_SCALE \
		--memory 2gb \
		--name firefox \
		--net host \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		--volume "${HOME}/.firefox/cache:/root/.cache/mozilla" \
		--volume "${HOME}/.firefox/mozilla:/root/.mozilla" \
		--volume "${HOME}/Downloads:/root/Downloads" \
		--volume "${HOME}/Pictures:/root/Pictures" \
		--volume "${HOME}/Torrents:/root/Torrents" \
		${DOCKER_REPO_PREFIX}/firefox "$@"

	# exit current shell
	exit 0
}

dfleetctl(){
	docker run --rm -it \
		--entrypoint fleetctl \
		--volume "${HOME}/.fleet://.fleet" \
		r.j3ss.co/fleet "$@"
}

dgcalcli(){
	docker run --rm -it \
		--name gcalcli \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume "${HOME}/.gcalcli/home:/home/gcalcli/home" \
		--volume "${HOME}/.gcalcli/work/oauth:/home/gcalcli/.gcalcli_oauth" \
		--volume "${HOME}/.gcalcli/work/gcalclirc:/home/gcalcli/.gcalclirc" \
		${DOCKER_REPO_PREFIX}/gcalcli "$@"
}

dgcloud(){
	docker run --rm -it \
		--name gcloud \
		--volume "${HOME}/.gcloud:/root/.config/gcloud" \
		--volume "${HOME}/.ssh:/root/.ssh:ro" \
		--volume "$(command --volume docker):/usr/bin/docker" \
		--volume /var/run/docker.sock:/var/run/docker.sock \
		${DOCKER_REPO_PREFIX}/gcloud "$@"
}

dgimp(){
	del_stopped gimp

	docker run -d \
		--env "DISPLAY=unix${DISPLAY}" \
		--env GDK_SCALE \
		--env GDK_DPI_SCALE \
		--name gimp \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		--volume "${HOME}/Pictures:/root/Pictures" \
		--volume "${HOME}/.gtkrc:/root/.gtkrc" \
		${DOCKER_REPO_PREFIX}/gimp
}

dgitsome(){
	docker run --rm -it \
		--name gitsome \
		--hostname gitsome \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume "${HOME}/.gitsomeconfig:/home/anon/.gitsomeconfig" \
		--volume "${HOME}/.gitsomeconfigurl:/home/anon/.gitsomeconfigurl" \
		${DOCKER_REPO_PREFIX}/gitsome
}

dhollywood(){
	docker run --rm -it \
		--name hollywood \
		${DOCKER_REPO_PREFIX}/hollywood
}

dhtop(){
	docker run --rm -it \
		--name htop \
		--net none \
		--pid host \
		${DOCKER_REPO_PREFIX}/htop
}

dhtpasswd(){
	docker run --rm -it \
		--name htpasswd \
		--net none \
		--log-driver none \
		${DOCKER_REPO_PREFIX}/htpasswd "$@"
}

dhttp(){
	docker run -t --rm \
		--log-driver none \
		--volume /var/run/docker.sock:/var/run/docker.sock \
		${DOCKER_REPO_PREFIX}/httpie "$@"
}

dimagemin(){
	local image=$1
	local extension="${image##*.}"
	local filename="${image%.*}"

	docker run --rm -it \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume "${HOME}/Pictures:/root/Pictures" \
		${DOCKER_REPO_PREFIX}/imagemin sh -c "imagemin /root/Pictures/${image} > /root/Pictures/${filename}_min.${extension}"
}

dirssi() {
	del_stopped irssi
	# relies_on notify_osd

	docker run --rm -it \
		--user root \
		--volume "${HOME}/.irssi:/home/user/.irssi" \
		${DOCKER_REPO_PREFIX}/irssi \
		chown -R user /home/user/.irssi

	docker run --rm -it \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume "${HOME}/.irssi:/home/user/.irssi" \
		--read-only \
		--name irssi \
		${DOCKER_REPO_PREFIX}/irssi
}

djohn(){
	local file
	file=$(realpath "$1")

	docker run --rm -it \
		--volume "${file}:/root/$(basename "${file}")" \
		${DOCKER_REPO_PREFIX}/john "$@"
}

dkernel_builder(){
	docker run --rm -it \
		--name kernel-builder \
		--volume /usr/src:/usr/src \
		--volume /lib/modules:/lib/modules \
		--volume /boot:/boot \
		${DOCKER_REPO_PREFIX}/kernel-builder
}

dkeypassxc(){
	del_stopped keypassxc

	docker run -d \
		--env "DISPLAY=unix${DISPLAY}" \
		--name keypassxc \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		--volume /usr/share/X11/xkb:/usr/share/X11/xkb:ro \
		--volume /etc/machine-id:/etc/machine-id:ro \
		${DOCKER_REPO_PREFIX}/keepassxc
}

dkicad(){
	del_stopped kicad

	docker run -d \
		--device /dev/dri \
		--env "DISPLAY=unix${DISPLAY}" \
		--env QT_DEVICE_PIXEL_RATIO \
		--env GDK_SCALE \
		--env GDK_DPI_SCALE \
		--name kicad \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		--volume "${HOME}/kicad:/root/kicad" \
		--volume "${HOME}/.cache/kicad:/root/.cache/kicad" \
		--volume "${HOME}/.config/kicad:/root/.config/kicad" \
		${DOCKER_REPO_PREFIX}/kicad
}

dkvm(){
	del_stopped kvm
	relies_on pulseaudio

	# modprobe the module
	modprobe kvm

	docker run -d \
		--env "DISPLAY=unix${DISPLAY}" \
		--env GDK_SCALE \
		--env GDK_DPI_SCALE \
		--env QT_DEVICE_PIXEL_RATIO \
		--env PULSE_SERVER=pulseaudio \
		--group-add audio \
		--link pulseaudio:pulseaudio \
		--name kvm \
		--privileged \
		--tmpfs /var/run \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		--volume "${HOME}/kvm:/root/kvm" \
		${DOCKER_REPO_PREFIX}/kvm
}

dlibreoffice(){
	del_stopped libreoffice

	docker run -d \
		--env "DISPLAY=unix${DISPLAY}" \
		--env GDK_SCALE \
		--env GDK_DPI_SCALE \
		--name libreoffice \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		--volume "${HOME}/slides:/root/slides" \
		${DOCKER_REPO_PREFIX}/libreoffice
}

dlpass(){
	docker run --rm -it \
		--name lpass \
		--volume "${HOME}/.lpass:/root/.lpass" \
		${DOCKER_REPO_PREFIX}/lpass "$@"
}

dlynx(){
	docker run --rm -it \
		--name lynx \
		${DOCKER_REPO_PREFIX}/lynx "$@"
}

dmasscan(){
	docker run -it --rm \
		--cap-add NET_ADMIN \
		--log-driver none \
		--name masscan \
		--net host \
		${DOCKER_REPO_PREFIX}/masscan "$@"
}

dmc(){
	cwd="$(pwd)"
	name="$(basename "$cwd")"

	docker run --rm -it \
		--log-driver none \
		--volume "${cwd}:/home/mc/${name}" \
		--workdir "/home/mc/${name}" \
		${DOCKER_REPO_PREFIX}/mc "$@"
}

dmpd(){
	del_stopped mpd

	# adding cap sys_admin so I can use nfs mount
	# the container runs as a unpriviledged user mpd
	docker run -d \
		--device /dev/snd \
		--cap-add SYS_ADMIN \
		--env MPD_HOST=/var/lib/mpd/socket \
		--name mpd \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /etc/exports:/etc/exports:ro \
		--volume "${HOME}/.mpd:/var/lib/mpd" \
		--volume "${HOME}/.mpd.conf:/etc/mpd.conf" \
		${DOCKER_REPO_PREFIX}/mpd
}

dmutt(){
	# subshell so we dont overwrite variables
	(
	local account=$1
	export IMAP_SERVER
	export SMTP_SERVER

	if [[ "$account" == "riseup" ]]; then
		export GMAIL=$MAIL_RISEUP
		export GMAIL_NAME=$MAIL_RISEUP_NAME
		export GMAIL_PASS=$MAIL_RISEUP_PASS
		export GMAIL_FROM=$MAIL_RISEUP_FROM
		IMAP_SERVER=mail.riseup.net
		SMTP_SERVER=$IMAP_SERVER
	fi

	docker run -it --rm \
		--env GMAIL \
		--env GMAIL_NAME \
		--env GMAIL_PASS \
		--env GMAIL_FROM \
		--env GPG_ID \
		--env IMAP_SERVER \
		--env SMTP_SERVER \
		--name "mutt-${account}" \
		--volume "${HOME}/.gnupg:/home/user/.gnupg:ro" \
		--volume /etc/localtime:/etc/localtime:ro \
		${DOCKER_REPO_PREFIX}/mutt
	)
}

dncmpc(){
	del_stopped ncmpc

	docker run --rm -it \
		--env MPD_HOST=/var/run/mpd/socket \
		--volume "${HOME}/.mpd/socket:/var/run/mpd/socket" \
		--name ncmpc \
		${DOCKER_REPO_PREFIX}/ncmpc "$@"
}

dneoman(){
	del_stopped neoman

	docker run -d \
		--device /dev/bus/usb \
		--device /dev/usb \
		--env "DISPLAY=unix${DISPLAY}" \
		--name neoman \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		${DOCKER_REPO_PREFIX}/neoman
}

dnes(){
	del_stopped nes
	local game=$1

	docker run -d \
		--device /dev/dri \
		--device /dev/snd \
		--env "DISPLAY=unix${DISPLAY}" \
		--name nes \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		${DOCKER_REPO_PREFIX}/nes "/games/${game}.rom"
}

dnetcat(){
	docker run --rm -it \
		--net host \
		${DOCKER_REPO_PREFIX}/netcat "$@"
}

dnginx(){
	del_stopped nginx

	docker run -d \
		--net host \
		--name nginx \
		--restart always \
		--volume "${HOME}/.nginx:/etc/nginx" \
		nginx

	# add domain to hosts & open nginx
	sudo hostess add jess 127.0.0.1
}

dnmap(){
	docker run --rm -it \
		--net host \
		${DOCKER_REPO_PREFIX}/nmap "$@"
}

dnotify_osd(){
	del_stopped notify_osd

	docker run -d \
		--env "DISPLAY=unix${DISPLAY}" \
		--name notify_osd \
		--net none \
		--volume /etc \
		--volume /home/user/.dbus \
		--volume /home/user/.cache/dconf \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		${DOCKER_REPO_PREFIX}/notify-osd
}

alias notify-send=dnotify_send
dnotify_send(){
	relies_on notify_osd
	local args=${*:2}
	docker exec -i notify_osd notify-send "$1" "${args}"
}

dnow(){
	docker run -it --rm \
		--log-driver none \
		--volume "${HOME}/.now:/root/.now" \
		--volume "$(pwd):/usr/src/repo:ro" \
		--workdir /usr/src/repo \
		${DOCKER_REPO_PREFIX}/now "$@"
}

dopenscad(){
	del_stopped openscad

	docker run -d \
		--device /dev/dri \
		--env "DISPLAY=unix${DISPLAY}" \
		--env QT_DEVICE_PIXEL_RATIO \
		--env GDK_SCALE \
		--env GDK_DPI_SCALE \
		--name openscad \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		--volume "${HOME}/openscad:/root/openscad" \
		--volume "${HOME}/.config/OpenSCAD:/root/.config/OpenSCAD" \
		${DOCKER_REPO_PREFIX}/openscad
}

dopensnitch(){
	del_stopped opensnitchd
	del_stopped opensnitch

	docker run -d \
		--cap-add NET_ADMIN \
		--env DBUS_SESSION_BUS_ADDRESS \
		--env XAUTHORITY \
		--name opensnitchd \
		--net host \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /etc/machine-id:/etc/machine-id:ro \
		--volume /var/run/dbus:/var/run/dbus \
		--volume /usr/share/dbus-1:/usr/share/dbus-1 \
		--volume "/var/run/user/$(id -u):/var/run/user/$(id -u)" \
		--volume "${HOME}/.Xauthority:$HOME/.Xauthority" \
		--volume /tmp:/tmp \
		${DOCKER_REPO_PREFIX}/opensnitchd

	docker run -d \
		--env "DISPLAY=unix${DISPLAY}" \
		--env DBUS_SESSION_BUS_ADDRESS \
		--env XAUTHORITY \
		--env HOME \
		--env QT_DEVICE_PIXEL_RATIO \
		--env XDG_RUNTIME_DIR \
		--name opensnitch \
		--net host \
		--user "$(id -u)" \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		--volume /usr/share/X11:/usr/share/X11:ro \
		--volume /usr/share/dbus-1:/usr/share/dbus-1 \
		--volume /etc/machine-id:/etc/machine-id:ro \
		--volume /var/run/dbus:/var/run/dbus \
		--volume "/var/run/user/$(id -u):/var/run/user/$(id -u)" \
		--volume "${HOME}/.Xauthority:$HOME/.Xauthority" \
		--volume /etc/passwd:/etc/passwd:ro \
		--volume /etc/group:/etc/group:ro \
		--volume /tmp:/tmp \
		--workdir "$HOME" \
		${DOCKER_REPO_PREFIX}/opensnitch
}

dosquery(){
	rmctr osquery

	docker run -d --restart always \
		--env OSQUERY_ENROLL_SECRET \
		--ipc host \
		--name osquery \
		--net host \
		--pid host \
		--privileged \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /var/run/docker.sock:/var/run/docker.sock \
		--volume /etc/os-release:/etc/os-release:ro \
		${DOCKER_REPO_PREFIX}/osquery \
		--verbose \
		--enroll_secret_env=OSQUERY_ENROLL_SECRET \
		--docker_socket=/var/run/docker.sock \
		--host_identifier=hostname \
		--tls_hostname="${OSQUERY_DOMAIN}" \
		--enroll_tls_endpoint=/api/v1/osquery/enroll \
		--config_plugin=tls \
		--config_tls_endpoint=/api/v1/osquery/config \
		--config_tls_refresh=10 \
		--disable_distributed=false \
		--distributed_plugin=tls \
		--distributed_interval=10 \
		--distributed_tls_max_attempts=3 \
		--distributed_tls_read_endpoint=/api/v1/osquery/distributed/read \
		--distributed_tls_write_endpoint=/api/v1/osquery/distributed/write \
		--logger_plugin=tls \
		--logger_tls_endpoint=/api/v1/osquery/log \
		--logger_tls_period=10
}

dpandoc(){
	local file=${*: -1}
	local lfile
	lfile=$(readlink -m "$(pwd)/${file}")
	local rfile
	rfile=$(readlink -m "/$(basename "$file")")
	local args=${*:1:${#@}-1}

	docker run --rm \
		--name pandoc \
		--volume "${lfile}:${rfile}" \
		--volume /tmp:/tmp \
		${DOCKER_REPO_PREFIX}/pandoc "${args}" "${rfile}"
}

dpivman(){
	del_stopped pivman

	docker run -d \
		--device /dev/bus/usb \
		--device /dev/usb \
		--env "DISPLAY=unix${DISPLAY}" \
		--name pivman \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		${DOCKER_REPO_PREFIX}/pivman
}

dpms(){
	del_stopped pms

	docker run --rm -it \
		--env MPD_HOST=/var/run/mpd/socket \
		--name pms \
		--volume "${HOME}/.mpd/socket:/var/run/mpd/socket" \
		${DOCKER_REPO_PREFIX}/pms "$@"
}

dpond(){
	del_stopped pond
	relies_on torproxy

	docker run --rm -it \
		--name pond \
		--net container:torproxy \
		${DOCKER_REPO_PREFIX}/pond
}

dprivoxy(){
	del_stopped privoxy
	relies_on torproxy

	docker run -d \
		--link torproxy:torproxy \
		--name privoxy \
		--publish 8118:8118 \
		--restart always \
		--volume /etc/localtime:/etc/localtime:ro \
		${DOCKER_REPO_PREFIX}/privoxy

	hostess add privoxy "$(docker inspect --format '{{.NetworkSettings.Networks.bridge.IPAddress}}' privoxy)"
}

dpulseaudio(){
	del_stopped pulseaudio

	docker run -d \
		--device /dev/snd \
		--group-add audio \
		--name pulseaudio \
		--publish 4713:4713 \
		--restart always \
		--volume /etc/localtime:/etc/localtime:ro \
		${DOCKER_REPO_PREFIX}/pulseaudio
}

drainbowstream(){
	docker run -it --rm \
		--name rainbowstream \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume "${HOME}/.rainbow_oauth:/root/.rainbow_oauth" \
		--volume "${HOME}/.rainbow_config.json:/root/.rainbow_config.json" \
		${DOCKER_REPO_PREFIX}/rainbowstream
}

dregistrator(){
	del_stopped registrator

	docker run -d --restart always \
		--name registrator \
		--net host \
		--volume /var/run/docker.sock:/tmp/docker.sock \
		gliderlabs/registrator consul:
}

dremmina(){
	del_stopped remmina

	docker run -d \
		--env "DISPLAY=unix${DISPLAY}" \
		--env GDK_SCALE \
		--env GDK_DPI_SCALE \
		--name remmina \
		--net host \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		--volume "${HOME}/.remmina:/root/.remmina" \
		${DOCKER_REPO_PREFIX}/remmina
}

dricochet(){
	del_stopped ricochet

	docker run -d \
		--device /dev/dri \
		--env "DISPLAY=unix${DISPLAY}" \
		--env GDK_SCALE \
		--env GDK_DPI_SCALE \
		--env QT_DEVICE_PIXEL_RATIO \
		--name ricochet \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		${DOCKER_REPO_PREFIX}/ricochet
}

drstudio(){
	del_stopped rstudio

	docker run -d \
		--device /dev/dri \
		--env "DISPLAY=unix${DISPLAY}" \
		--env QT_DEVICE_PIXEL_RATIO \
		--name rstudio \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		--volume "${HOME}/fastly-logs:/root/fastly-logs" \
		--volume /dev/shm:/dev/shm \
		${DOCKER_REPO_PREFIX}/rstudio
}

ds3cmdocker(){
	del_stopped s3cmd

	docker run --rm -it \
		--env AWS_ACCESS_KEY="${DOCKER_AWS_ACCESS_KEY}" \
		--env AWS_SECRET_KEY="${DOCKER_AWS_ACCESS_SECRET}" \
		--name s3cmd \
		--volume "$(pwd):/root/s3cmd-workspace" \
		${DOCKER_REPO_PREFIX}/s3cmd "$@"
}

dscudcloud(){
	del_stopped scudcloud

	docker run -d \
		--device /dev/snd \
		--env "DISPLAY=unix${DISPLAY}" \
		--env TERM \
		--env XAUTHORITY \
		--env DBUS_SESSION_BUS_ADDRESS \
		--env HOME \
		--env QT_DEVICE_PIXEL_RATIO \
		--name scudcloud \
		--user "$(whoami)" --workdir "$HOME" \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		--volume /etc/machine-id:/etc/machine-id:ro \
		--volume /var/run/dbus:/var/run/dbus \
		--volume "/var/run/user/$(id -u):/var/run/user/$(id -u)" \
		--volume /etc/passwd:/etc/passwd:ro \
		--volume /etc/group:/etc/group:ro \
		--volume "${HOME}/.Xauthority:$HOME/.Xauthority" \
		--volume "${HOME}/.scudcloud:/home/jessie/.config/scudcloud" \
		${DOCKER_REPO_PREFIX}/scudcloud

	# exit current shell
	exit 0
}

dshorewall(){
	del_stopped shorewall

	docker run --rm -it \
		--cap-add NET_ADMIN \
		--name shorewall \
		--net host \
		--privileged \
		${DOCKER_REPO_PREFIX}/shorewall "$@"
}

dskype(){
	del_stopped skype
	relies_on pulseaudio

	docker run -d \
		--device /dev/video0 \
		--env "DISPLAY=unix${DISPLAY}" \
		--env PULSE_SERVER=pulseaudio \
		--group-add video \
		--group-add audio \
		--link pulseaudio:pulseaudio \
		--name skype \
		--security-opt seccomp:unconfined \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		${DOCKER_REPO_PREFIX}/skype

}

dslack(){
	del_stopped slack

	docker run -d \
		--device /dev/snd \
		--device /dev/dri \
		--device /dev/video0 \
		--env "DISPLAY=unix${DISPLAY}" \
		--group-add audio \
		--group-add video \
		--ipc="host" \
		--name slack \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		--volume "${HOME}/.slack:/root/.config/Slack" \
		${DOCKER_REPO_PREFIX}/slack "$@"
}

dspotify(){
	del_stopped spotify

	docker run -d \
		--env "DISPLAY=unix${DISPLAY}" \
		--env QT_DEVICE_PIXEL_RATIO \
		--device /dev/snd \
		--device /dev/dri \
		--group-add audio \
		--group-add video \
		--name spotify \
		--security-opt seccomp:unconfined \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		${DOCKER_REPO_PREFIX}/spotify
}

dssh2john(){
	local file
	file=$(realpath "$1")

	docker run --rm -it \
		--entrypoint ssh2john \
		--volume "${file}:/root/$(basename "${file}")" \
		${DOCKER_REPO_PREFIX}/john "$@"
}

dsshb0t(){
	del_stopped sshb0t

	if [[ ! -d "${HOME}/.ssh" ]]; then
		mkdir --publish "${HOME}/.ssh"
	fi

	if [[ ! -f "${HOME}/.ssh/authorized_keys" ]]; then
		touch "${HOME}/.ssh/authorized_keys"
	fi

	GITHUB_USER=${GITHUB_USER:=jessfraz}

	docker run --rm -it \
		--name sshb0t \
		--volume "${HOME}/.ssh/authorized_keys:/root/.ssh/authorized_keys" \
		r.j3ss.co/sshb0t \
		--user "${GITHUB_USER}" --keyfile /root/.ssh/authorized_keys --once
}

dsteam(){
	del_stopped steam
	relies_on pulseaudio

	docker run -d \
		--env "DISPLAY=unix${DISPLAY}" \
		--device /dev/dri \
		--env PULSE_SERVER=pulseaudio \
		--link pulseaudio:pulseaudio \
		--name steam \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /etc/machine-id:/etc/machine-id:ro \
		--volume /var/run/dbus:/var/run/dbus \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		--volume "${HOME}/.steam:/home/steam" \
		${DOCKER_REPO_PREFIX}/steam

}

dt(){
	docker run -t --rm \
		--log-driver none \
		--volume "${HOME}/.trc:/root/.trc" \
		${DOCKER_REPO_PREFIX}/t "$@"
}

dtarsnap(){
	docker run --rm -it \
		--volume "${HOME}/.tarsnaprc:/root/.tarsnaprc" \
		--volume "${HOME}/.tarsnap:/root/.tarsnap" \
		--volume "$HOME:/root/workdir" \
		${DOCKER_REPO_PREFIX}/tarsnap "$@"
}

dtelnet(){
	docker run -it --rm \
		--log-driver none \
		${DOCKER_REPO_PREFIX}/telnet "$@"
}

dtermboy(){
	del_stopped termboy
	local game=$1

	docker run --rm -it \
		--device /dev/snd \
		--name termboy \
		${DOCKER_REPO_PREFIX}/nes "/games/${game}.rom"
}

dterraform(){
	docker run -it --rm \
		--env GOOGLE_APPLICATION_CREDENTIALS \
		--env SSH_AUTH_SOCK \
		--log-driver none \
		--volume "${HOME}:${HOME}:ro" \
		--volume "$(pwd):/usr/src/repo" \
		--volume /tmp:/tmp \
		--workdir /usr/src/repo \
		${DOCKER_REPO_PREFIX}/terraform "$@"
}

dtor(){
	del_stopped tor

	docker run -d \
		--name tor \
		--net host \
		${DOCKER_REPO_PREFIX}/tor

	# set up the redirect iptables rules
	sudo setup-tor-iptables

	# validate we are running through tor
	browser-exec "https://check.torproject.org/"
}

dtorbrowser(){
	del_stopped torbrowser

	docker run -d \
		--env "DISPLAY=unix${DISPLAY}" \
		--env GDK_SCALE \
		--env GDK_DPI_SCALE \
		--device /dev/snd \
		--name torbrowser \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		${DOCKER_REPO_PREFIX}/tor-browser

	# exit current shell
	exit 0
}

dtormessenger(){
	del_stopped tormessenger

	docker run -d \
		--env "DISPLAY=unix${DISPLAY}" \
		--env GDK_SCALE \
		--env GDK_DPI_SCALE \
		--device /dev/snd \
		--name tormessenger \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		${DOCKER_REPO_PREFIX}/tor-messenger

	# exit current shell
	exit 0
}

dtorproxy(){
	del_stopped torproxy

	docker run -d \
		--name torproxy \
		--publish 9050:9050 \
		--restart always \
		--volume /etc/localtime:/etc/localtime:ro \
		${DOCKER_REPO_PREFIX}/tor-proxy

	hostess add torproxy "$(docker inspect --format '{{.NetworkSettings.Networks.bridge.IPAddress}}' torproxy)"
}

dtraceroute(){
	docker run --rm -it \
		--net host \
		${DOCKER_REPO_PREFIX}/traceroute "$@"
}

dtransmission(){
	del_stopped transmission

	docker run -d \
		--name transmission \
		--publish 9091:9091 \
		--publish 51413:51413 \
		--publish 51413:51413/udp \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume "${HOME}/Torrents:/transmission/download" \
		--volume "${HOME}/.transmission:/transmission/config" \
		${DOCKER_REPO_PREFIX}/transmission


	hostess add transmission "$(docker inspect --format '{{.NetworkSettings.Networks.bridge.IPAddress}}' transmission)"
	browser-exec "http://transmission:9091"
}

dtravis(){
	docker run -it --rm \
		--log-driver none \
		--volume "${HOME}/.travis:/root/.travis" \
		--volume "$(pwd):/usr/src/repo:ro" \
		--workdir /usr/src/repo \
		${DOCKER_REPO_PREFIX}/travis "$@"
}

dvirsh(){
	relies_on kvm

	docker run -it --rm \
		--log-driver none \
		--net container:kvm \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /run/libvirt:/var/run/libvirt \
		${DOCKER_REPO_PREFIX}/libvirt-client "$@"
}

dvirtualbox(){
	del_stopped virtualbox

	docker run -d \
		--env "DISPLAY=unix${DISPLAY}" \
		--name virtualbox \
		--privileged \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		${DOCKER_REPO_PREFIX}/virtualbox
}

dvirt_viewer(){
	relies_on kvm

	docker run -it --rm \
		--env "DISPLAY=unix${DISPLAY}" \
		--env PULSE_SERVER=pulseaudio \
		--group-add audio \
		--log-driver none \
		--net container:kvm \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix  \
		--volume /run/libvirt:/var/run/libvirt \
		${DOCKER_REPO_PREFIX}/virt-viewer "$@"
}

alias virt-viewer="dvirt_viewer"
dvscode(){
	del_stopped visualstudio

	docker run -d \
		--env "DISPLAY=unix${DISPLAY}" \
		--device /dev/dri \
		--name visualstudio \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix  \
		${DOCKER_REPO_PREFIX}/vscode
}

alias vscode="dvisualstudio"
dvlc(){
	del_stopped vlc
	relies_on pulseaudio

	docker run -d \
		--device /dev/dri \
		--env "DISPLAY=unix${DISPLAY}" \
		--env GDK_SCALE \
		--env GDK_DPI_SCALE \
		--env QT_DEVICE_PIXEL_RATIO \
		--env PULSE_SERVER=pulseaudio \
		--group-add audio \
		--group-add video \
		--link pulseaudio:pulseaudio \
		--name vlc \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		--volume "${HOME}/Torrents:/home/vlc/Torrents" \
		${DOCKER_REPO_PREFIX}/vlc
}

dwatchman(){
	del_stopped watchman

	docker run -d \
		--name watchman \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume "${HOME}/Downloads:/root/Downloads" \
		${DOCKER_REPO_PREFIX}/watchman --foreground
}

dweematrix(){
	del_stopped weematrix

	docker run --rm -it \
		--user root \
		--volume "${HOME}/.weechat:/home/user/.weechat" \
		${DOCKER_REPO_PREFIX}/weechat-matrix \
		chown -R user /home/user/.weechat

	docker run --rm -it \
		--env "TERM=screen" \
		--name weematrix \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume "${HOME}/.weechat:/home/user/.weechat" \
		${DOCKER_REPO_PREFIX}/weechat-matrix
}

dweeslack(){
	del_stopped weeslack

	docker run --rm -it \
		--user root \
		--volume "${HOME}/.weechat:/home/user/.weechat" \
		${DOCKER_REPO_PREFIX}/wee-slack \
		chown -R user /home/user/.weechat

	docker run --rm -it \
		--name weeslack \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume "${HOME}/.weechat:/home/user/.weechat" \
		${DOCKER_REPO_PREFIX}/wee-slack
}

dwg(){
	docker run -i --rm \
		--cap-add NET_ADMIN \
		--log-driver none \
		--name wg \
		--net host \
		--volume /tmp:/tmp \
		${DOCKER_REPO_PREFIX}/wg "$@"
}

dwireshark(){
	del_stopped wireshark

	docker run -d \
		--cap-add NET_RAW \
		--cap-add NET_ADMIN \
		--env "DISPLAY=unix${DISPLAY}" \
		--name wireshark \
		--net host \
		--volume /etc/localtime:/etc/localtime:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix \
		${DOCKER_REPO_PREFIX}/wireshark
}

dwrk(){
	docker run -it --rm \
		--log-driver none \
		--name wrk \
		${DOCKER_REPO_PREFIX}/wrk "$@"
}

dykman(){
	del_stopped ykpersonalize

	docker run --rm -it \
		--device /dev/usb \
		--device /dev/bus/usb \
		--name ykman \
		--volume /etc/localtime:/etc/localtime:ro \
		${DOCKER_REPO_PREFIX}/ykman bash
}

dykpersonalize(){
	del_stopped ykpersonalize

	docker run --rm -it \
		--device /dev/usb \
		--device /dev/bus/usb \
		--name ykpersonalize \
		--volume /etc/localtime:/etc/localtime:ro \
		${DOCKER_REPO_PREFIX}/ykpersonalize bash
}

alias yubico-piv-tool="dyubico_piv_tool"
dyubico_piv_tool(){
	del_stopped yubico-piv-tool

	docker run --rm -it \
		--device /dev/usb \
		--device /dev/bus/usb \
		--name yubico-piv-tool \
		--volume /etc/localtime:/etc/localtime:ro \
		${DOCKER_REPO_PREFIX}/yubico-piv-tool bash
}

# ------------------------------------------------------------------------------
# Impromptu Prompt Segment Function
# ------------------------------------------------------------------------------
impromptu::prompt::docker() {
  IMPROMPTU_DOCKER_SHOW="true"
  IMPROMPTU_DOCKER_PREFIX=""
  IMPROMPTU_DOCKER_SUFFIX=" "
  IMPROMPTU_DOCKER_SYMBOL="🐳 "
  IMPROMPTU_DOCKER_COLOR="cyan"
  IMPROMPTU_DOCKER_VERBOSE="false"

  chk::command docker || return

  [[ "$IMPROMPTU_DOCKER_SHOW" == "true" ]] || return

  # Better support for docker environment vars: https://docs.docker.com/compose/reference/envvars/
  local compose_exists=false
  if [[ -n "$COMPOSE_FILE" ]]
  then
    # Use COMPOSE_PATH_SEPARATOR or colon as default
    local separator=${COMPOSE_PATH_SEPARATOR:-":"}

    # COMPOSE_FILE may have several filenames separated by colon, test all of them
    local filenames=("${(@ps/$separator/)COMPOSE_FILE}")

    for filename in $filenames
    do
      if [[ ! -f $filename ]]
      then
        compose_exists=false
        break
      fi
      compose_exists=true
    done

    # Must return if COMPOSE_FILE is present but invalid
    [[ "$compose_exists" == false ]] && return
  fi

  # Show Docker status only for Docker-specific folders
  [[ "$compose_exists" == true || -f Dockerfile || -f docker-compose.yml || -f /.dockerenv ]] || return

  # if docker daemon isn't running you'll get an error saying it can't connect
  local docker_version=$(docker version -f "{{.Server.Version}}" 2>/dev/null)
  [[ -z $docker_version ]] && return

  [[ $IMPROMPTU_DOCKER_VERBOSE == false ]] && docker_version=${docker_version%-*}

  if [[ -n $DOCKER_MACHINE_NAME ]]
  then
    docker_version+=" via ($DOCKER_MACHINE_NAME)"
  fi

  impromptu::segment "$IMPROMPTU_DOCKER_COLOR" \
    "${IMPROMPTU_DOCKER_PREFIX}${IMPROMPTU_DOCKER_SYMBOL}v${docker_version}${IMPROMPTU_DOCKER_SUFFIX}"
}
