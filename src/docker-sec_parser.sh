#!/bin/bash

APPARMOR_D_PATH=/etc/apparmor.d
DOCKER_LIB_PATH=/var/lib/docker
DS_PROFILE_PATH=$APPARMOR_D_PATH/docker-sec
DS_TUNABLES_PATH=$DS_PROFILE_PATH/tunables
DS_RUNTIME_PATH=$DS_PROFILE_PATH/runtime
DS_PIV_ROOT_PATH=$DS_PROFILE_PATH/pivot_root
DS_DOCK_RUNC_PATH=/etc/apparmor.d/usr.bin.docker-runc
DS_RUNTIME_DEF=$DS_PROFILE_PATH/docker-sec-runtime
DS_PIV_ROOT_DEF=$DS_PROFILE_PATH/docker-sec-pivot

bold_text=$(tput bold)
normal_text=$(tput sgr0)

#source docker-sec_utils.sh

add_to_tunable_glob(){
	check_if_root "add_to_tunable_glob:"	

	local path=$DS_TUNABLES_PATH/docker-sec-glob	

#	if [ $DEBUG ]; then 
#		if [[ $# -ne 4 ]]; then
#			echo "Not enough arguments provided"
#			return 1
#		else
#			echo "updating tunable_glob"
#		fi
#	fi

	if [ -z $(grep "@{CONTAINER_MOUNT_POINTS}" $path |grep "$cont_mount") ]; then
		sed -i "s/@{CONTAINER_MOUNT_POINTS}={/@{CONTAINER_MOUNT_POINTS}={$cont_mount,/" $path
	fi

	if [ -z $(grep "@{CONTAINER_IDS}" $path |grep "$cont_id") ]; then
		sed -i "s/@{CONTAINER_IDS}={/@{CONTAINER_IDS}={$cont_id,/" $path
	fi
	
	if [ -z $(grep "@{CONTAINER_BOOT_PROFILES}" $path |grep "$cont_boot_prof") ]; then
                sed -i "s/@{CONTAINER_BOOT_PROFILES}={/@{CONTAINER_BOOT_PROFILES}={$cont_boot_prof,/" $path
        fi

	if [ -z $(grep "@{CONTAINER_RUNTIME_PROFILES}" $path |grep "$cont_run_prof") ]; then 
                sed -i "s/@{CONTAINER_RUNTIME_PROFILES}={/@{CONTAINER_RUNTIME_PROFILES}={$cont_run_prof,/" $path
        fi
}

clean_tunables(){
	local path=$DS_TUNABLES_PATH/docker-sec-glob

	[[ -n ${cont_mount} ]] && #check if cont_mount is null
	if [ -n $(grep "@{CONTAINER_MOUNT_POINTS}" $path |grep "$cont_mount") ]; then
		sed -i "s/${cont_mount},//" $path
	fi
	
	[[ -n ${cont_boot_prof} ]] &&
	if [ -n $(grep "@{CONTAINER_BOOT_PROFILES}" $path |grep "$cont_boot_prof") ]; then #must be before cont id
                sed -i "s/${cont_boot_prof},//" $path
        fi

	[[ -n ${cont_id} ]] &&
	if [ -n $(grep "@{CONTAINER_IDS}" $path |grep "$cont_id") ]; then
		sed -i "s/${cont_id},//" $path
	fi

	[[ -n ${cont_run_prof} ]] &&
	if [ -n $(grep "@{CONTAINER_RUNTIME_PROFILES}" $path |grep "$cont_run_prof") ]; then
                sed -i "s/${cont_run_prof},//" $path
        fi

}

add_to_tunables(){
	add_to_tunable_glob
}

create_default_runtime(){
	check_if_root "create_default_runtime:"

	cp -i $DS_RUNTIME_DEF $DS_RUNTIME_PATH/$1
	sed -i "s#docker-sec-default#$1#" $DS_RUNTIME_PATH/$1
	aa-enforce "$DS_RUNTIME_PATH/$1"

}

create_logprof_train_runtime(){
	#usage create_logprof_train_runtime: CONT_RUNTIME_PROF
	check_if_root "create_logprof_train_runtim:"

	cp -i ${DS_RUNTIME_DEF}-complain ${DS_RUNTIME_PATH}/$1
	sed -i "s#docker-sec-default#$1#" $DS_RUNTIME_PATH/$1
	aa-complain "$DS_RUNTIME_PATH/$1"

}

create_pivot_root(){
	check_if_root "create_pivot_root:"

	cp -i $DS_PIV_ROOT_DEF $DS_PIV_ROOT_PATH/$cont_boot_prof	
	sed -i "s/@@/$cont_boot_prof/" $DS_PIV_ROOT_PATH/$cont_boot_prof
	sed -i "s/::/$cont_run_prof/" $DS_PIV_ROOT_PATH/$cont_boot_prof
	change_user_support ${cont_id}
	aa-enforce $DS_PIV_ROOT_PATH/$cont_boot_prof	
}


update_docker_runc(){                                 #TODO: better parsing
	check_if_root "update_docker_runc:"

	local out=""
	local rule="pivot_root @{MOUNT_POINT_AUFS_DOCKER}/$1/ -> $2,\n"
	while read line; do
	        out="${out}${line}\n"
	        if [[ "$line" =~ profile\ /usr/bin/docker-runc.*\{ ]]; then
	                out="${out}\t${rule}"
	                break
	        fi
	done
	mount_regex="[[:space:]]*#[[:space:]]*audit mount,"
	while read line; do
	        #print "$line"
	        out="${out}\t${line}\n"
		if [[ "$line" =~ ${mount_regex} ]]; then
			out="${out}$(experimental_volumes_to_docker_runc ${3})\n"
			break
		fi
	done

	while read line; do
		out="${out}\t${line}\n"

	done
	
	echo -e "$out"    > $APPARMOR_D_PATH/usr.bin.docker-runc

	aa-enforce $APPARMOR_D_PATH/usr.bin.docker-runc
	
}

add_volumes_to_docker_runc(){
	if [ -z $1 ]; then
                echo "${bold_text}add_volumes_to_docker_runc:${normal_text} Please provide container name"
                return 1
        fi

        cont_name=${1}
	cont_mount_path="$(container_mount_point $cont_id)" || return 1
        res=$(docker inspect -f '{{ range .Mounts }}{{ .Source}} {{ .Destination }} {{end}}' $1) #{{ printf "\n" }}
	
	if [[ -z $res ]];then
		debug_out "${bold_text}add_volumes_to_docker_runc:${normal_text} No volumes found!"
	fi
#TODO: review	
        while [[ ! "$res" =~ ^[[:space:]]*$ ]]; do
                sourceP=$(expr "$res" : '\([^ ]*\) ')
		[[ "$sourceP" =~ /$ ]] || sourceP="${sourceP}/"
                destP=$(expr "$res" : '[^ ]* \([^ ]*\) ')
		[[ "$destP" =~ /$ ]] || destP="${destP}/"
                echo "\tmount ${sourceP} -> ${DOCKER_LIB_PATH}/aufs/mnt/${cont_mount_path}${destP},"
                res=${res#[^ ]* [^ ]* }
        done
}

experimental_volumes_to_docker_runc(){
	if [ -z $1 ]; then
                echo "${bold_text}add_volumes_to_docker_runc:${normal_text} Please provide container name"
                return 1
        fi

        cont_name=${1}
	cont_mount_path="$(container_mount_point $cont_id)" || return 1
        res=$(docker inspect -f '{{ range .Mounts }}{{ .Source}} {{ .Destination }} "{{ .RW }} "{{ .Propagation }} {{end}}' $1) #{{ printf "\n" }}
	
	if [[ -z $res ]];then
		debug_out "${bold_text}add_volumes_to_docker_runc:${normal_text} No volumes found!"
	fi
#TODO: review	
        while [[ ! "$res" =~ ^[[:space:]]*$ ]]; do
                sourceP=$(expr "$res" : '\([^ ]*\) ')
#		[[ "$sourceP" =~ /$ ]] || sourceP="${sourceP}/"
                destP=$(expr "$res" : '[^ ]* \([^ ]*\) ')
#		[[ "$destP" =~ /$ ]] || destP="${destP}/"
		rw=$(expr "$res" : '[^ ]* [^ ]* \([^ ]*\) ')		
		rw=${rw:1}
		prop=$(expr "$res" : '[^ ]* [^ ]* [^ ]* \([^ ]*\) ')
		prop=${prop:1}
		if [[ -d ${sourceP} ]]; then
			[[ "$sourceP" =~ /$ ]] || sourceP="${sourceP}/"
			[[ "$destP" =~ /$ ]] || destP="${destP}/"
		fi
		if [[ $rw == false ]]; then
			rw="option = (ro,remount,rbind) "
		else
			rw=""
		fi
                echo "\tmount ${sourceP} -> ${DOCKER_LIB_PATH}/aufs/mnt/${cont_mount_path}${destP},"
		if [[ -n ${prop} ]]; then
			echo "\tmount option in (${prop}) -> ${DOCKER_LIB_PATH}/aufs/mnt/${cont_mount_path}${destP},"
		fi
		[[ -n ${rw} ]] && echo "\tmount ${rw} -> ${DOCKER_LIB_PATH}/aufs/mnt/${cont_mount_path}${destP},"

                res=${res#[^ ]* [^ ]* [^ ]* [^ ]* }
        done

}

apply_cap_train(){
	if [ -z $1 ]; then
                echo "usage: ${bold_text}apply_cap_train${normal_text} CONTAINER_RUNTIME_PROFILE" >&2
                return 1
        fi

	profile=$1
	prof_path="/etc/apparmor.d/docker-sec/runtime/${profile}"
	
	grep "apparmor=\"AUDIT\" operation=\"capable\" profile=\"${profile}\"" /var/log/audit/audit.log |
	while read line
	do
	        cap=$(echo ${line} | sed -r 's/.*capname="(.*)"/\1/')
	        if [[ -z $(grep ${cap} ${prof_path}) ]]; then
	        	info_out "Docker-sec: adding ${cap} capability to ${profile} profile"
	                sed -i "/capability_placeholder,/ a\  capability ${cap}," ${prof_path}
	        fi
	done
	sed -i '/audit capability,/d' ${prof_path}
	aa-enforce ${prof_path}
	
}

apply_net_cap_train(){
	if [ -z $1 ]; then
                echo "usage: ${bold_text}apply_net_cap_train${normal_text} CONTAINER_RUNTIME_PROFILE" >&2
                return 1
        fi

	profile=$1
	prof_path="/etc/apparmor.d/docker-sec/runtime/${profile}"
	
	grep "profile=\"${profile}\"" /var/log/audit/audit.log |
	grep "apparmor=\"AUDIT\""|
	grep "sock_type" |
	sed -r 's/.*family="(.*)" sock_type="(.*)" protocol.*/network \1 \2,/'|
	# sed -r sed -r 's/.*family="(.*)" sock_type=.*/network \1,/'|
	sort -u |
	while read net_rule
	do
	        if [[ -z $(grep "${net_rule}" ${prof_path}) ]]; then
	        	info_out "Docker-sec: adding the network rule: \"${net_rule}\" to ${profile} profile"
	                sed -i "/network_placeholder,/ a\  ${net_rule}" ${prof_path}
	        fi
	done
	sed -i '/audit network,/d' ${prof_path}
	aa-enforce ${prof_path}
	
}

change_user_support(){
	if [ -z $1 ]; then
                echo "usage: ${bold_text}change_user_support${normal_text} CONTAINER_NAME" >&2
                return 1
        fi
	if [[ -z "$(docker inspect -f '{{.Config.User}}' ${1})" ]]; then
		debug_out "${bold_text}change_user_support:${normal_text} No user found!"	
		return 0;
	fi
	local cont_id=$(container_full_id $1)
	local cont_boot_prof=$(pivot_root_profile_name $cont_id)
	sed -i '/capability setuid,/ a\\tcapability chown,' $DS_PIV_ROOT_PATH/$cont_boot_prof

	

}

reload_container_profiles(){	#TODO: option for complain mode
	if [ -z $1 ]; then
		echo "usage: reload_container_profiles CONTAINER_NAME" >&2
		return 1
	fi

	container_exists $1 
	if [ $? -ne 0 ]; then
		echo "Cannot reload profiles of a non-existing container" >&2
		return 1
	fi

	check_if_root "reload_container_profiles:"

	local cont_id=$(container_full_id $1)
	local cont_boot_prof=$(pivot_root_profile_name $cont_id)
	local cont_run_prof=$(run_time_profile_name $cont_id)
	aa-enforce $APPARMOR_D_PATH/usr.bin.docker-runc $DS_PIV_ROOT_PATH/$cont_boot_prof $DS_RUNTIME_PATH/$cont_run_prof
}

#change_container_profile(){ #TODO: review
#	local path=$DOCKER_LIB_PATH/containers/$cont_id/config.v2.json
#	sed -i "s/\"AppArmorProfile\":\"\"/\"AppArmorProfile\":\"$cont_run_prof\"/" $path
#}


create_default_profile(){	
	if [ -z $1 ]; then
		echo "usage: create_default_profile CONTAINER_NAME" >&2
		return 1
	fi
	container_exists $1 
	if [ $? -ne 0 ]; then
		echo "Cannot create profile for a non-existing container" >&2
		return 1
	fi
		
	check_if_root "create_default_profile:"	

	local cont_id=$(container_full_id $1)
		debug_out "Container id $cont_id"
	local cont_mount=$(container_mount_point $cont_id)
		debug_out "Container mount point $cont_mount"
	local cont_boot_prof=$(pivot_root_profile_name $cont_id)
		debug_out "Container boot profile $cont_boot_prof"
	local cont_run_prof=$(run_time_profile_name $cont_id)
		debug_out "Container runtime profile $cont_run_prof"
	
#	change_container_profile

	add_to_tunables
	if [[ -n "$(ls $DS_RUNTIME_PATH/ | grep $cont_run_prof)" ]]; then
		prompt_yes_no "Do you want to override existing profile: $cont_run_prof ? [Y/N]: " 
	fi &&
	create_default_runtime $cont_run_prof
	
	if [[ -n "$(ls $DS_PIV_ROOT_DEF $DS_PIV_ROOT_PATH/ | grep $cont_boot_prof)" ]]; then
		prompt_yes_no "Do you want to override existing profile: $cont_boot_prof ? [Y/N]: "
	fi &&
	create_pivot_root

	if [[ -z $(grep $cont_mount $APPARMOR_D_PATH/usr.bin.docker-runc) ]]; then
	  (update_docker_runc $cont_mount $cont_boot_prof $1 < $APPARMOR_D_PATH/usr.bin.docker-runc)
	fi

	debug_out "Profile generation completed! (probably successfully)"
}

cleanup_container_profiles(){	

	if [ -z $1 ]; then
		echo "usage: cleanup_container_profile CONTAINER_NAME" >&2
		return 1
	fi

	container_exists $1 
	if [ $? -ne 0 ]; then
		echo "Cannot cleanup profiles for a non-existing container" >&2
		return 1
	fi
	
	if [[ -n $(docker ps|grep ${1}) ]]; then
		echo "Warning: Container $1 still running" >&2
	fi
		
	check_if_root "cleanup_container_profile:"	

	local cont_id=$(container_full_id $1)
		debug_out "Container id $cont_id"
	local cont_mount=$(container_mount_point $cont_id)
		debug_out "Container mount point $cont_mount"
	local cont_boot_prof=$(pivot_root_profile_name $cont_id)
		debug_out "Container boot profile $cont_boot_prof"
	local cont_run_prof=$(run_time_profile_name $cont_id)
		debug_out "Container runtime profile $cont_run_prof"
	

	clean_tunables
	if [ -e ${DS_RUNTIME_PATH}/${cont_run_prof} ]; then
		prompt_yes_no "Are you sure u want to remove profile: $cont_run_prof ? [Y/N]: " &&
		aa-disable "${DS_RUNTIME_PATH}/${cont_run_prof}" &&
		rm "${DS_RUNTIME_PATH}/${cont_run_prof}"
	fi
	
	if [ -e ${DS_PIV_ROOT_PATH}/${cont_boot_prof} ]; then
		prompt_yes_no "Are you sure u want to remove profile: $cont_boot_prof ? [Y/N]: " &&
		aa-disable "${DS_PIV_ROOT_PATH}/${cont_boot_prof}" &&
		rm "${DS_PIV_ROOT_PATH}/${cont_boot_prof}"
	fi

	if [[ -n $(grep ${cont_mount} ${APPARMOR_D_PATH}/usr.bin.docker-runc) ]]; then
		sed -i "/${cont_boot_prof}/d" ${APPARMOR_D_PATH}/usr.bin.docker-runc
		sed -i "/${cont_mount}/d" ${APPARMOR_D_PATH}/usr.bin.docker-runc
		aa-enforce ${APPARMOR_D_PATH}/usr.bin.docker-runc
	fi

	debug_out "Profile cleanup completed! (Please check results)"
}	
