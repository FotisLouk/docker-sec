#!/bin/bash

E_NOARGS=75
E_INVARGS=76


bold_text=$(tput bold)
normal_text=$(tput sgr0)

DEBUG=1
INFO=1
#set -x
docker_sec_dir=$(dirname "$0")
source "${docker_sec_dir}/docker-sec_parser.sh"

docker-sec-help(){
	echo "docker-sec usage:"
	echo "   ${bold_text}docker-sec COMMAND [ARGUMENTS]${normal_text}"; echo;	#support [OPTIONS] ?
	echo "COMMANDS:"
	echo "    run          Run a command in a new Apparmor contained container"
	echo "    start        Start one or more stopped containers"
	echo "    stop         Stop one or more running containers"
	echo "    ps           List running/created containers"
	echo "    rm           Remove a container that is no longer running"
	echo "    create       Create a new container along with the required Apparmor profiles"
	echo "    attach       Attach to an existing container"
	echo "    stats        Display a live stream of container(s) resource usage statistics"
	echo "    pull         Pull docker image from repository"
	echo "    inspect      Show container configuration"
	echo "    volume       Manage Docker volumes"
	echo "    train-start  Start train period of container"
	echo "    train-stop   Stop container's train period and enforce the appropriate profile"
	echo "    info         Display docker-sec info and profiles associated with the given container"
	echo "    exec         Run a command in a running container"
	echo ;
	echo "run ${bold_text}docker COMMAND help${normal_text} for available arguments for a specific command"

}

container_exists(){
	if [ -z $1 ]; then
		echo "usage: ${bold_text}container_exists CONTAINER_NAME|CONTAINER_ID${normal_text}" >&2
		exit $E_NOARGS
	fi
	if [ -n "$(docker ps -a --no-trunc| grep -w $1)" ]; then 	#[[ -n $(docker ps -a | grep -w $1) ]]
		debug_out "Container ${bold_text}$1${normal_text} exists!"
		return 0
	fi
	debug_out "Container ${bold_text}$1${normal_text} does ${bold_text}NOT${normal_text} exist"
	return 1
}

container_started(){
	if [ -z $1 ]; then
                echo "usage: ${bold_text}container_started CONTAINER_NAME|CONTAINER_ID${normal_text}" >&2
                exit $E_NOARGS
        fi
        if [ -n "$(docker ps --no-trunc | grep -w $1)" ]; then  #[[ -n $(docker ps -a | grep -w $1) ]]
                debug_out "Container ${bold_text}$1${normal_text} is started!"
                return 0
        fi
        debug_out "Container ${bold_text}$1${normal_text} is ${bold_text}NOT${normal_text} started"
        return 1
}

container_mount_point(){
	if [ -z $1 ]; then
                echo "usage: ${bold_text}container_mount_point CONTAINER_ID${normal_text}" >&2
                exit $E_NOARGS
        fi
	cat /var/lib/docker/image/aufs/layerdb/mounts/$1/mount-id #requires sudo
}

container_full_id(){
	if [ -z $1 ]; then
                echo "usage: ${bold_text}container_full_id CONTAINER_NAME${normal_text}" >&2
                exit $E_NOARGS
        fi
	docker ps -a --no-trunc |grep -w $1|cut -d' ' -f1
}

container_get_name(){
	if [ -z $1 ]; then
                echo "usage: ${bold_text}container_get_name CONTAINER_ID${normal_text}" >&2
                exit $E_NOARGS
        fi
	docker ps --format "table {{.Names}}\t{{.ID}}" -a --no-trunc |grep -w $1|cut -d' ' -f1
}

pivot_root_profile_name(){  #given an id return the name of pivot_profile
	if [ -z $1 ]; then
		echo "usage: ${bold_text}pivot_root_profile_name CONTAINER_ID${normal_text}" >&2
		exit $E_NOARGS
        fi
        echo "pivot_root_$1"

}


generate_run_time_profile_name(){
	echo  "docker_$(openssl rand -hex 20)"

}

run_time_profile_name(){   #given the container id return the name of run time porfile
	check_if_root "run_time_profile_name:"

	if [ -z $1 ]; then
                echo "usage: ${bold_text}run_time_profile_name CONTAINER_ID${normal_text}" >&2
                exit $E_NOARGS
        fi
	grep -o -e "AppArmorProfile\":\"docker_[A-Za-z0-9]*" "/var/lib/docker/containers/$1/config.v2.json" | cut -d'"' -f3
}

pretty_print_container_config(){
	if [ -z $1 ]; then
                echo "usage: ${bold_text}get_container_config CONTAINER_ID${normal_text}" >&2
                exit $E_NOARGS
        fi
	cat "/var/lib/docker/containers/$1/config.v2.json"
}

debug_out(){
	if [ $DEBUG ]
	then
		echo $1 >&2
	fi
}

info_out(){
	if [ $INFO ]
	then
		echo $1 >&2
	fi
}

prompt_yes_no(){
	prompt=$1	
	while true; do
		read -r -p "$prompt" response
		if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
			return 0
		fi
	
		if [[ "$response" =~ ^([nN][oO]|[nN])+$ ]]; then
			return 1
		fi
	done
}

check_if_root(){
	if [ -z $1 ]; then
		echo "usage: ${bold_text}check_if_root MESSAGE${normal_text}" >&2
                exit $E_NOARGS
        fi
:
	if [[ $(id -u) != "0" ]]; then
		echo "${bold_text}${1}${normal_text} must be run as ${bold_text}root${normal_text}" >&2
		return 1
	fi
	return 0

}


profile_exists(){
	check_if_root "profile_exists:"	

	if [ -z $1 ]; then
                echo "usage: ${bold_text}profile_exists PROFILE_NAME${normal_text}" >&2
                exit $E_NOARGS
        fi

	if [ -z "$(aa-status |grep -w $1)" ]
	then
		return 1
	else
		return 0
	fi	
}

container_profile_exists(){
	check_if_root "container_profile_exists:"	

	if [ -z $1 ]; then
                echo "usage: ${bold_text}cotnainer_profile_exists CONTAINER_NAME${normal_text}" >&2
                exit $E_NOARGS
        fi
	
	container_id=$(container_full_id $1)
	if [ -z "$container_id" ]; then
		echo "${bold_text}container_profile_exists: ${normal_text}container does not exist" >&2
		return 1
	fi	

	runtime_prof="$(run_time_profile_name $container_id)"
	if [ -z "$runtime_prof" ]; then
		echo "${bold_text}container_profile_exists: ${normal_text}No runtime profile assigned to container" >&2
		return 1
	fi	
	
	profile_exists "$runtime_prof"
}

#extract_cont_name_drun(){
#	for arg in "$@"; do
#		case arg in
#			-*)
#				:;;
#			*)
#				echo $arg
#				return 0
#		esac
#	done
#}

docker-sec_create(){
	check_if_root "docker-sec_create: "	

	if [[ "$1" =~ create|run ]]; then  
		shift
	fi

	local cont_runtime_prof=$(generate_run_time_profile_name)
	local cont_id=$(docker create --security-opt apparmor=$cont_runtime_prof "$@" || echo "-1")
	if [ $? -ne 0 -o "${cont_id}" == "-1" ]; then
		echo "${bold_text}Docker-sec_create:${normal_text} Something went wrong during container creation" >&2
		return 1
	fi
	local cont_name=$(container_get_name $cont_id)
	create_default_profile $cont_name
	echo $cont_name	
}

docker-sec_run(){
	check_if_root "docker-sec_run: "	

	for arg do
		shift
		[ "$arg" = "-d" ] && continue
		set -- "$@" "$arg"
	done


	local cont_name=$(docker-sec_create $@ || echo "-1")
	if [ $? -ne 0 -o "${cont_name}" == "-1" ]; then
		echo "${bold_text}Docker-sec_run:${normal_text} Something went wrong during container creation" >&2
		return 1
	fi

	docker-sec_start start "${cont_name##*$'\n'}"
}

docker-sec_stop(){
	docker $@ #review
}

docker-sec_ps(){
	docker $@
}

docker-sec_attach(){
	docker $@
}

docker-sec_stats(){
	docker $@
}

docker-sec_pull(){
	docker $@
}

docker-sec_inspect(){
	docker $@
}

docker-sec_volume(){
	docker $@
}

docker-sec_info(){
	shift
	if [ -z $1 ]; then
		echo "usage: ${bold_text}docker-sec_info${normal_text} CONTAINER_NAME"
		exit $E_NOARGS
	fi

	container_id=$(container_full_id $1)
	mount_point=$(container_mount_point ${container_id})
	runtime_prof="$(run_time_profile_name $container_id)"
	piv_root_prof="$(pivot_root_profile_name ${container_id})"

	echo "Container Name: $1"
	echo "Container Id: ${container_id}"
	echo "Mount path: ${mount_point}"
	echo "Runtime Profile: ${runtime_prof}"
	echo "Boot Profile: ${piv_root_prof}"
}

docker-sec_exec(){
	docker $@
}

docker-sec_train-start_help(){
	echo "usage: ${bold_text}docker-sec_train-start${normal_text} [OPTIONS] CONTAINER_NAME"
	echo
	echo "OPTIONS:"
	echo "          -f,--full:  create container profile from scratch using log-prof"
	echo "          -h,--help:  display help"

}

docker-sec_train-start(){
	shift
	if [ -z $1 ]; then
		docker-sec_train-start_help
		exit $E_NOARGS
	fi

	local full=0

	case $1 in
		-f|--full)
			full=1
			shift;;
		-h|--help)
			docker-sec_train-start_help
			return 0;;
		*)
			;;
	esac
	
	
	container_exists $1 || return 1
	service auditd rotate
	
	container_id=$(container_full_id $1)
	debug_out "train-start: containerId: ${container_id}"

	runtime_prof="$(run_time_profile_name $container_id)"
	debug_out "train-start: runtimeProf ${runtime_prof}"

	if [[ ${full} -eq 1 ]]
	then
		create_logprof_train_runtime $runtime_prof
		return 0
	fi

	#train with increasing priviledges (starting from a baseline profile)	
	if [[ -n $(grep "capability[[:space:]]*," /etc/apparmor.d/docker-sec/runtime/${runtime_prof}) ]]; then
		[[ -z $(grep "audit capability," /etc/apparmor.d/docker-sec/runtime/${runtime_prof}) ]] &&
		sed -i 's/capability,/audit capability,/' /etc/apparmor.d/docker-sec/runtime/${runtime_prof}
	else
		sed -i '/capability_placeholder,/ a\  audit capability,' /etc/apparmor.d/docker-sec/runtime/${runtime_prof}
	fi
	
        if [[ -n $(grep "network[[:space:]]*," /etc/apparmor.d/docker-sec/runtime/${runtime_prof}) ]]; then
		[[ -z $(grep "audit network," /etc/apparmor.d/docker-sec/runtime/${runtime_prof}) ]] &&
                sed -i 's/network,/audit network,/' /etc/apparmor.d/docker-sec/runtime/${runtime_prof}
        else
                sed -i '/network_placeholder,/ a\  audit network,' /etc/apparmor.d/docker-sec/runtime/${runtime_prof}
        fi


	aa-enforce /etc/apparmor.d/docker-sec/runtime/${runtime_prof}

}

docker-sec_train-stop(){
	shift
	if [ -z $1 ]; then
		echo "usage: ${bold_text}docker-sec_train-stop CONTAINER_NAME${normal_text}"
		exit $E_NOARGS
	fi

	container_id=$(container_full_id $1)
	debug_out "train-stop: containerId: ${container_id}"

	runtime_prof="$(run_time_profile_name $container_id)"
	debug_out "train-stop: runtimeProf ${runtime_prof}"
	runtime_prof_path=/etc/apparmor.d/docker-sec/runtime/${runtime_prof}


	if [ $(wc -l ${runtime_prof_path} | cut -d' ' -f1) -lt 20 ];then
		debug_out "Train ending!"
		aa-logprof -d /etc/apparmor.d/docker-sec/runtime
		aa-enforce ${runtime_prof_path}
		return 0
	fi
	
	apply_cap_train "${runtime_prof}"	
	apply_net_cap_train "${runtime_prof}" 
}

docker-sec_start(){
	for arg in ${@:2:$#}
	do
		case $arg in
			-a|-i|-ai|-ia)
				;;
			-*)
				echo "Invalid argument" >&2
				exit $E_INVARGS	;;
			*)
				if [ "$(container_profile_exists $arg)" == "1" ]; then		#add user prompt?
					echo "WARNING: docker-sec profile not found" >&2
				fi 
		esac
	done
	docker $@
}

docker-sec_rm_help(){
	echo "usage: docker-sec rm [OPTS] [DOCKER_OPTS] CONTAINER_NAME|CONTAINER_ID${normal_text}";echo
        echo "Remove container and the associated directories and files";echo
        echo "Options:";
        echo "--help: Display help"
        echo "-p:     Remove Apparmor profiles for this container"
	echo "-o:     Remove ONLY Apparmor profiles for this container"
	echo "Docker options:"
	echo "-f,--force:     Force remove (SIGKILL) container"
	echo "-l, --link:      Remove the specified link"
}


docker-sec_rm(){
	shift
	if [ -z $1 ]; then
		docker-sec_rm_help
		exit $E_NOARGS
	fi

	if [ $1 == "--help" -o $1 == "help" ]; then
		docker-sec_rm_help
        fi

	local cont_name="${@:$#}"

	if [ $1 == "-p" ]; then
		cleanup_container_profiles "$cont_name"  || return 1 
		shift
	fi
	
	if [ $1 == "-o" ]; then
		cleanup_container_profiles "$cont_name"
		return 0
	fi

	if [ -z $1 ]; then
		docker-sec_rm_help >&2
		exit $E_NOARGS
	fi

	docker rm $@
}

