#!/bin/bash

SCRIPT='git-simple-notifier'
CONFIG="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/.$SCRIPT.config"

notifyCallback() { # $1=text
	echo "$1"
}

notifyPushCallback() { # $1=text
	echo "$1"
}

loopCallback() {
	return 0
}

if [ -f "$CONFIG" ]; then
	source "$CONFIG" \
		|| { echo ERR 1 "$CONFIG" >&2; exit 1; }
fi

###

requiredDirs() {
	for D in "$@"; do
		[ -z "$D" ] && continue
		mkdir -p "$D" \
			|| { echo ERR 2 >&2; exit 2; }
	done
}

requiredUtils() { # $@:RequiredUtils
	for U in "$@"; do
		which "$U" > /dev/null
		[ 0 == $? ] \
			|| { echo ERR 3 "'$U' is required." >&2; exit 3; }
	done
}

init() { # $1:UserOrOrganization $*:Repositories
	O=$1
	shift
	for R in $*; do
		[ -d "$DIR_CONFIG/$R" ] && continue
		mkdir "$DIR_CONFIG/$R" \
			&& cd "$DIR_CONFIG/$R" \
			&& git init \
			&& git remote add origin git@github.com:$O/$R.git \
			|| { echo ERR 11 >&2; exit 11; }
	done
}

###

notify() { # $2:Type $3:Priority $3:Kind $4:Title $5:Message
	priority="$3"; kind="$4"; title="$(notifyCallback "$5")"; message="$(notifyCallback "$6")"
	echo; echo "$kind: $title"; echo "$message"
	if [ "$2" == 'all' ] || [ "$2" == 'desktop' ]; then
		notify-send -u critical "$kind: $title" "$message" \
			|| echo ERR 21 >&2
	fi
	if [ "$2" == 'all' ] || [ "$2" == 'push' ]; then
		curl -H "Priority: $priority" -H "Tags: $SCRIPT,$kind" -H "Title: $kind: $(notifyPushCallback "$title")" -d "$(notifyPushCallback "$message")" ntfy.sh/$NTFY_TOPIC \
			|| echo ERR 22 >&2
	fi
}

checkGit() { # $2:NotificationType $3:NotificationPriority $@:GitDirectories
	notification="$2"; priority="$3"; shift 3; echo
	for dirGit in "$@"; do
		repository=${dirGit##*/}; fileLog="$DIR_CACHE/$repository.git.log"; fileOld="$DIR_CACHE/$repository.git.log.old"
		if [ -f "$fileLog" ]; then
			cat "$fileLog" > "$fileOld" \
				|| { echo ERR 31 >&2; continue; }
		fi
		cd "$dirGit" \
			&& git fetch --all \
			&& git log -$LOG_LINES --all --pretty=format:'%ai %S%n%an: %s' > "$fileLog" \
			&& echo >> "$fileLog" \
			|| { echo ERR 32 >&2; continue; }
		if [ -f "$fileOld" ]; then
			diff=$(diff --unchanged-line-format= --old-line-format= "$fileOld" "$fileLog")
			[ -n "$diff" ] && notify '' "$notification" "$priority" Commits "$repository" "$diff"
		fi
	done
}

checkGithub() { # $2:NotificationType $3:NotificationPriority $@:Organizations
	notification="$2"; priority="$3"; shift 3; echo
	for organization in "$@"; do
		fileLog="$DIR_CACHE/$organization.api.repos"; fileOld="$DIR_CACHE/$organization.api.repos.old"
		if [ -f "$fileLog" ]; then
			cat "$fileLog" > "$fileOld" \
				|| { echo ERR 41 >&2; continue; }
		fi
		curl -su "$GITHUB_TOKEN:x-oauth-basic" https://api.github.com/orgs/$organization/repos | grep '"name"' | cut -d'"' -f4 > "$fileLog" \
			|| { echo ERR 42 >&2; continue; }
		if [ -f "$fileOld" ]; then
			diff=$(diff "$fileOld" "$fileLog")
			[ -n "$diff" ] && notify '' "$notification" "$priority" Repositories "$organization" "$diff"
		fi
	done
}

###

if [ "$1" == 'init' ]; then
	requiredDirs "$DIR_CONFIG"
	requiredUtils mkdir git
	init $Organization $ListRepositories

elif [ "$1" == 'check-git' ]; then
	requiredDirs "$DIR_CACHE" "$DIR_CONFIG"
	requiredUtils mkdir git cat diff
	[[ "$2" == 'all' || "$2" == 'desktop' ]] && requiredUtils notify-send
	[[ "$2" == 'all' || "$2" == 'push' ]] && requiredUtils curl
	checkGit '' "$2" $NtfyPriorityRepositories $DIR_CONFIG/*
	checkGit '' "$2" $NtfyPriorityDirectories $ListRepositoryDirectories

elif [ "$1" == 'check-api' ]; then
	requiredDirs "$DIR_CACHE"
	requiredUtils mkdir git cat diff curl
	[[ "$2" == 'all' || "$2" == 'desktop' ]] && requiredUtils notify-send
	checkGithub '' "$2" $NtfyPriorityOrganizations $ListOrganizations

elif [ "$1" == 'check' ]; then
	requiredDirs "$DIR_CACHE" "$DIR_CONFIG"
	requiredUtils mkdir git cat diff curl
	[[ "$2" == 'all' || "$2" == 'desktop' ]] && requiredUtils notify-send
	checkGit '' "$2" $NtfyPriorityRepositories $DIR_CONFIG/*
	checkGit '' "$2" $NtfyPriorityDirectories $ListRepositoryDirectories
	checkGithub '' "$2" $NtfyPriorityOrganizations $ListOrganizations

elif [ "$1" == 'loop' ]; then
	requiredDirs "$DIR_CACHE" "$DIR_CONFIG"
	requiredUtils mkdir git cat diff curl
	[[ "$2" == 'all' || "$2" == 'desktop' ]] && requiredUtils notify-send
	while true; do
		loopCallback
		if [ 0 == $? ]; then
			checkGit '' "$2" $NtfyPriorityRepositories $DIR_CONFIG/*
			checkGit '' "$2" $NtfyPriorityDirectories $ListRepositoryDirectories
			checkGithub '' "$2" $NtfyPriorityOrganizations $ListOrganizations
		fi
		echo $SCRIPT $(date) sleep $SLEEP_TIME ...
		sleep $SLEEP_TIME
	done

else
	echo 'Usage: $SCRIPT.sh init'
	echo 'Usage: $SCRIPT.sh Action [Notification]'
	echo '  Action      : check-git | check-api | check | loop'
	echo '  Notification: desktop | push | all'
	echo 'Version 1.0 / License GPLv3 / Author plamenjm(at)gmail.com'
fi
