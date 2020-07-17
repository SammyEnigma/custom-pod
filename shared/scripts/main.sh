#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC1117,SC2153,SC2214
set -eou pipefail

pod_vars_dir="$POD_VARS_DIR"
pod_layer_dir="$POD_LAYER_DIR"
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

. "${pod_vars_dir}/vars.sh"

GRAY='\033[0;90m'
RED='\033[0;31m'
NC='\033[0m' # No Color

function info {
	msg="$(date '+%F %T') - ${1:-}"
	>&2 echo -e "${GRAY}${msg}${NC}"
}

function error {
	msg="$(date '+%F %T') - ${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${1:-}"
	>&2 echo -e "${RED}${msg}${NC}"
	exit 2
}

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered (env - shared)."
fi

shift;

args=("$@")

pod_env_run_file="$pod_layer_dir/main/scripts/main.sh"
nginx_run_file="$pod_layer_dir/$var_shared__script_dir/services/nginx.sh"
nextcloud_run_file="$pod_layer_dir/$var_shared__script_dir/services/nextcloud.sh"

case "$command" in
	"upgrade")
		if [ "${var_custom__use_main_network:-}" = "true" ]; then
			"$pod_env_run_file" "setup:main:network"
		fi

		"$pod_env_run_file" "$command" "$@"
		;;
	"prepare")
		info "$command - do nothing..."
		;;
	"local:prepare")
		"$arg_ctl_layer_dir/run" dev-cmd bash "/root/w/r/$arg_env_local_repo/run" ${arg_opts[@]+"${arg_opts[@]}"}
		;;
	"backup")
		if [ "${var_custom__use_logrotator:-}" = "true" ]; then
			"$pod_env_run_file" run logrotator
		fi

		"$pod_env_run_file" "$command" "$@"
		;;
	"setup")
		data_dir="/var/main/data"

		"$pod_script_env_file" up "toolbox"

		"$pod_script_env_file" exec-nontty "toolbox" /bin/bash <<-SHELL
			set -eou pipefail

			if [ "${var_custom__use_nginx:-}" = "true" ]; then
				if [ "$var_custom__pod_type" = "app" ] || [ "$var_custom__pod_type" = "web" ]; then
					dir_nginx="$data_dir/sync/nginx"

					dir="\${dir_nginx}/auto"
					file="\${dir}/ips-blacklist-auto.conf"

					if [ ! -f "\$file" ]; then
						mkdir -p "\$dir"
						cat <<-EOF > "\$file"
							# 127.0.0.1 1;
							# 1.2.3.4/16 1;
						EOF
					fi

					dir="\${dir_nginx}/manual"
					file="\${dir}/ips-blacklist.conf"

					if [ ! -f "\$file" ]; then
						mkdir -p "\$dir"
						cat <<-EOF > "\$file"
							# 127.0.0.1 1;
							# 0.0.0.0/0 1;
						EOF
					fi

					dir="\${dir_nginx}/manual"
					file="\${dir}/ua-blacklist.conf"

					if [ ! -f "\$file" ]; then
						mkdir -p "\$dir"
						cat <<-EOF > "\$file"
							# ~(Mozilla|Chrome) 1;
							# "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/83.0.4103.106 Safari/537.36" 1;
							# "python-requests/2.18.4" 1;
						EOF
					fi

					dir="\${dir_nginx}/manual"
					file="\${dir}/allowed-hosts.conf"

					if [ ! -f "\$file" ]; then
						mkdir -p "\$dir"
						cat <<-EOF > "\$file"
							# *.googlebot.com
							# *.google.com
						EOF
					fi
				fi
			fi

			if [ "${var_custom__use_mysql:-}" = "true" ]; then
				if [ "$var_custom__pod_type" = "app" ] || [ "$var_custom__pod_type" = "db" ]; then
					dir="$data_dir/mysql"

					if [ ! -d "\$dir" ]; then
						mkdir -p "\$dir"
						chmod 755 "\$dir"
					fi

					dir="$data_dir/tmp/mysql"

					if [ ! -d "\$dir" ]; then
						mkdir -p "\$dir"
						chmod 777 "\$dir"
					fi

					dir="$data_dir/tmp/log/mysql"

					if [ ! -d "\$dir" ]; then
						mkdir -p "\$dir"
						chmod 777 "\$dir"
					fi
				fi
			fi
		SHELL

		"$pod_env_run_file" "$command" "$@"
		;;
	"migrate")
		if [ "${var_custom__use_certbot:-}" = "true" ]; then
			info "$command - start certbot if needed..."
			"$pod_script_env_file" "main:task:certbot"
		fi

		if [ "${var_custom__use_nextcloud:-}" = "true" ]; then
			info "$command - prepare nextcloud..."
			"$pod_script_env_file" "shared:service:nextcloud:setup"
		fi
		;;
	"shared:service:nextcloud:setup")
		"$pod_script_env_file" "service:nextcloud:setup" \
			--task_name="nextcloud" \
			--subtask_cmd="$command" \
			--admin_user="$var_shared__nextcloud__setup__admin_user" \
			--admin_pass="$var_shared__nextcloud__setup__admin_pass" \
			--nextcloud_url="$var_shared__nextcloud__setup__url" \
			--nextcloud_domain="$var_shared__nextcloud__setup__domain" \
			--nextcloud_host="$var_shared__nextcloud__setup__host" \
			--nextcloud_protocol="$var_shared__nextcloud__setup__protocol"

		"$pod_script_env_file" "service:nextcloud:fs" \
			--task_name="nextcloud_action" \
			--subtask_cmd="$command" \
			--mount_point="/action" \
			--datadir="/var/main/data/action"

		"$pod_script_env_file" "service:nextcloud:fs" \
			--task_name="nextcloud_data" \
			--subtask_cmd="$command" \
			--mount_point="/data" \
			--datadir="/var/main/data"

		"$pod_script_env_file" "service:nextcloud:fs" \
			--task_name="nextcloud_sync" \
			--subtask_cmd="$command" \
			--mount_point="/sync" \
			--datadir="/var/main/data/sync"

		if [ "${var_shared__nextcloud__s3_backup__enable:-}" = "true" ]; then
			"$pod_script_env_file" "service:nextcloud:s3" \
				--task_name="nextcloud_backup" \
				--subtask_cmd="$command" \
				--mount_point="/backup" \
				--bucket="$var_shared__nextcloud__s3_backup__bucket" \
				--hostname="$var_shared__nextcloud__s3_backup__hostname" \
				--port="$var_shared__nextcloud__s3_backup__port" \
				--region="$var_shared__nextcloud__s3_backup__region" \
				--use_ssl="$var_shared__nextcloud__s3_backup__use_ssl" \
				--use_path_style="$var_shared__nextcloud__s3_backup__use_path_style" \
				--legacy_auth="$var_shared__nextcloud__s3_backup__legacy_auth"  \
				--key="$var_shared__nextcloud__s3_backup__access_key" \
				--secret="$var_shared__nextcloud__s3_backup__secret_key"
		fi

		if [ "${var_shared__nextcloud__s3_uploads__enable:-}" = "true" ]; then
			"$pod_script_env_file" "service:nextcloud:s3" \
				--task_name="nextcloud_uploads" \
				--subtask_cmd="$command" \
				--mount_point="/uploads" \
				--bucket="$var_shared__nextcloud__s3_uploads__bucket" \
				--hostname="$var_shared__nextcloud__s3_uploads__hostname" \
				--port="$var_shared__nextcloud__s3_uploads__port" \
				--region="$var_shared__nextcloud__s3_uploads__region" \
				--use_ssl="$var_shared__nextcloud__s3_uploads__use_ssl" \
				--use_path_style="$var_shared__nextcloud__s3_uploads__use_path_style" \
				--legacy_auth="$var_shared__nextcloud__s3_uploads__legacy_auth"  \
				--key="$var_shared__nextcloud__s3_uploads__access_key" \
				--secret="$var_shared__nextcloud__s3_uploads__secret_key"
		fi
		;;
	"action:exec:block_ips")
		case "$var_custom__pod_type" in
			"app"|"web")
				;;
			*)
				error "$command: pod_type ($var_custom__pod_type) not supported"
				;;
		esac

		if [ "${var_custom__use_fluentd:-}" != "true" ]; then
				error "$command: fluentd must be used"
		fi

		log_hour_path_prefix="/var/log/main/fluentd/main/docker.nginx/docker.nginx.stdout"
		tmp_base_path="/tmp/main/run/block_ips"
		tmp_last_day_file="${tmp_base_path}/last_day.log"
		tmp_day_file="${tmp_base_path}/day.log"

		"$pod_script_env_file" exec-nontty toolbox /bin/bash <<-SHELL
			set -eou pipefail

			log_last_day_src_path_prefix="$log_hour_path_prefix.$(date -u -d '1 day ago' '+%Y-%m-%d')"
			log_day_src_path_prefix="$log_hour_path_prefix.$(date -u '+%Y-%m-%d')"

			mkdir -p "$tmp_base_path"

			echo "" > "$tmp_last_day_file"
			echo "" > "$tmp_day_file"

			for i in \$(seq -f "%02g" 1 24); do
				log_last_day_src_path_aux="\$log_last_day_src_path_prefix.\$i.log"
				log_day_src_path_aux="\$log_day_src_path_prefix.\$i.log"

				if [ -f "\$log_last_day_src_path_aux" ]; then
					cat "\$log_last_day_src_path_aux" >> "$tmp_last_day_file"
				fi

				if [ -f "\$log_day_src_path_aux" ]; then
					cat "\$log_day_src_path_aux" >> "$tmp_day_file"
				fi
			done
		SHELL

		nginx_sync_base_dir="/var/main/data/sync/nginx"

		"$pod_script_env_file" "service:nginx:block_ips" \
			--task_name="block_ips" \
			--subtask_cmd="$command" \
			--max_ips="$var_shared__block_ips__action_exec__max_ips" \
			--output_file="$nginx_sync_base_dir/auto/ips-blacklist-auto.conf" \
			--manual_file="$nginx_sync_base_dir/manual/ips-blacklist.conf" \
			--allowed_hosts_file="$nginx_sync_base_dir/manual/allowed-hosts.conf" \
			--log_file_last_day="$tmp_last_day_file" \
			--log_file_day="$tmp_day_file" \
			--amount_day="$var_shared__block_ips__action_exec__amount_day" \
			--log_file_hour="$log_hour_path_prefix.$(date -u '+%Y-%m-%d.%H').log" \
			--log_file_last_hour="$log_hour_path_prefix.$(date -u -d '1 hour ago' '+%Y-%m-%d.%H').log" \
			--amount_hour="$var_shared__block_ips__action_exec__amount_hour"
		;;
	"action:exec:nginx_reload")
		"$pod_script_env_file" "service:nginx:reload" "${@}"
		;;
	"action:subtask:"*)
		task_name="${command#action:subtask:}"

		opts=()

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--toolbox_service=toolbox" )
		opts+=( "--action_dir=/var/main/data/action" )

		"$pod_env_run_file" "action:subtask" "${opts[@]}"
		;;
	"service:nginx:"*)
		"$nginx_run_file" "$command" \
			--toolbox_service="toolbox" \
			--nginx_service="nginx" \
			"${@}"
		;;
	"service:nextcloud:"*)
		"$nextcloud_run_file" "$command" \
			--toolbox_service="toolbox" \
			--nextcloud_service="nextcloud" \
			"${@}"
		;;
	*)
		"$pod_env_run_file" "$command" ${args[@]+"${args[@]}"}
		;;
esac
