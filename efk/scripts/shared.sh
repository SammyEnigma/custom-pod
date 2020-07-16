#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC2153
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
	error "No command entered (env)."
fi

shift;

pod_env_run_file="$pod_layer_dir/main/scripts/main.sh"

case "$command" in
	"upgrade")
		"$pod_env_run_file" "setup:main:network"
		"$pod_env_run_file" "$command" "$@"
		;;
	"setup")
		data_dir="/var/main/data"

		"$pod_script_env_file" up "$var_run__general__toolbox_service"

		"$pod_script_env_file" exec-nontty "$var_run__general__toolbox_service" /bin/bash <<-SHELL
			if [ "$var_custom__pod_type" = "app" ] || [ "$var_custom__pod_type" = "db" ]; then
				dir="$data_dir/elasticsearch"

				if [ ! -d "\$dir" ]; then
					mkdir -p "\$dir"
					chmod 755 "\$dir"
				fi
			fi

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
		SHELL

		"$pod_env_run_file" "$command" "$@"
		;;
	"migrate")
		"$pod_script_env_file" "migrate:$var_custom__pod_type" ${args[@]+"${args[@]}"}

		if [ "${var_custom__use_certbot:-}" = "true" ]; then
			info "$command - start certbot if needed..."
			"$pod_script_env_file" "main:task:certbot"
		fi

		if [ "${var_custom__use_nextcloud:-}" = "true" ]; then
			info "$command - prepare nextcloud..."
			"$pod_script_env_file" "migrate:custom:nextcloud"
		fi
		;;
	"migrate:app")
		"$pod_script_env_file" "migrate:web" ${args[@]+"${args[@]}"}
		"$pod_script_env_file" "migrate:db" ${args[@]+"${args[@]}"}
		;;
	"migrate:web")
		info "$command - nothing to do..."
		;;
	"migrate:db")
		vm_max_map_count="${var_migrate_es_vm_max_map_count:-262144}"
		info "$command increasing vm max map count to $vm_max_map_count"
		sudo sysctl -w vm.max_map_count="$vm_max_map_count"
		;;
	"migrate:custom:nextcloud")
		"$nextcloud_run_file" "nextcloud:setup" \
			--task_name="nextcloud" \
			--subtask_cmd="$command" \
			--toolbox_service="$var_run__general__toolbox_service" \
			--nextcloud_service="nextcloud" \
			--admin_user="$var_custom__nextcloud_admin_user" \
			--admin_pass="$var_custom__nextcloud_admin_pass" \
			--nextcloud_url="$var_custom__nextcloud_url" \
			--nextcloud_domain="$var_custom__nextcloud_domain" \
			--nextcloud_host="$var_custom__nextcloud_host" \
			--nextcloud_protocol="$var_custom__nextcloud_protocol"

		"$nextcloud_run_file" "nextcloud:fs" \
			--task_name="nextcloud_action" \
			--subtask_cmd="$command" \
			--toolbox_service="$var_run__general__toolbox_service" \
			--nextcloud_service="nextcloud" \
			--mount_point="/action" \
			--datadir="/var/main/data/action"

		"$nextcloud_run_file" "nextcloud:fs" \
			--task_name="nextcloud_data" \
			--subtask_cmd="$command" \
			--toolbox_service="$var_run__general__toolbox_service" \
			--nextcloud_service="nextcloud" \
			--mount_point="/data" \
			--datadir="/var/main/data"

		"$nextcloud_run_file" "nextcloud:fs" \
			--task_name="nextcloud_sync" \
			--subtask_cmd="$command" \
			--toolbox_service="$var_run__general__toolbox_service" \
			--nextcloud_service="nextcloud" \
			--mount_point="/sync" \
			--datadir="/var/main/data/sync"

		"$nextcloud_run_file" "nextcloud:s3" \
			--task_name="nextcloud_backup" \
			--subtask_cmd="$command" \
			--toolbox_service="$var_run__general__toolbox_service" \
			--nextcloud_service="nextcloud" \
			--mount_point="/backup" \
			--bucket="$var_custom__s3_backup_bucket" \
			--hostname="$var_custom__s3_backup_hostname" \
			--port="$var_custom__s3_backup_port" \
			--region="$var_custom__s3_backup_region" \
			--use_ssl="$var_custom__s3_backup_use_ssl" \
			--use_path_style="$var_custom__s3_backup_use_path_style" \
			--legacy_auth="$var_custom__s3_backup_legacy_auth"  \
			--key="$var_custom__s3_backup_access_key" \
			--secret="$var_custom__s3_backup_secret_key"
		;;
	"actions")
		"$pod_script_env_file" "action:subtask:nginx_reload"
		;;
	"action:subtask:"*)
		task_name="${command#action:subtask:}"

		opts=()

		opts+=( "--task_name=$task_name" )
		opts+=( "--subtask_cmd=$command" )

		opts+=( "--toolbox_service=$var_run__general__toolbox_service" )
		opts+=( "--action_dir=/var/main/data/action" )

		"$pod_env_run_file" "action:subtask" "${opts[@]}"
		;;
	"action:exec:nginx_reload")
		"$pod_env_run_file" exec-nontty nginx nginx -s reload
		;;
	*)
		"$pod_env_run_file" "$command" "$@"
		;;
esac