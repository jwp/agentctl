#!/bin/sh
# System command level controls for Chrome.
# Presumes the "Google Chrome" variant. Adjustments are necessary for "Chromium".
#
# [ Implementation ]
#
# This particular solution exclusively uses AppleScript, (system/command)`osascript`, to dispatch
# instructions to a *running* instance of Google Chrome.
#
# [ References ]
# https://chromium.googlesource.com/chromium/src/+/f74d7ed2fd9792ed79b26a6512e7ba3df5f90eef/chrome/browser/ui/cocoa/applescript/examples
# https://discussions.apple.com/thread/6820749
# https://apple.stackexchange.com/questions/141213/grab-the-active-window-in-applescript
##
OSASCRIPT='osascript'
CHROME_APPLICATION='/Applications/Google Chrome.app'
CHROME_EXECUTABLE="$CHROME_APPLICATION"'/Contents/MacOS/Google Chrome'

# Interpolated into AppleScript.
CHROME_ID='id "com.google.Chrome"'
SYSTEM_EVENTS_ID='id "com.apple.SystemEvents"'
APP_OPEN='tell application '"$CHROME_ID"
APP_CLOSE='end tell'
TAB_ID='active tab' # or tab 1, tab 2, etc
WINDOW_ID='window 1'

# Rather undesirable property of most chrome interactions being that they will activate windows.
# Often, we want to dispatch reload/move/etc while maintaining the active application.
# In order to compensate, this mess is used before and after most AE tells.
STORE_FOCUS='tell application id "com.apple.SystemEvents" to set frontmostApplicationName to name of 1st process whose frontmost is true'
RESTORE_FOCUS='tell application frontmostApplicationName to activate'

# Protect strings interpolated into AppleScript statements.
astr ()
{
	echo "$1" | sed 's/"/\\"/g;s/\\/\\\\/g'
}

# Default wrapper for most operations.
osaretain ()
{
	"$OSASCRIPT" \
		-e "$STORE_FOCUS" \
		"$@" \
		-e "$RESTORE_FOCUS"
}

# Overridden to osascript when focus should be shifted to chrome(-f).
AE_EXECUTE='osaretain'

execution_trace ()
{
	# Overridden when -g.
	"$@"
}

# Common invocation.
tell_chrome ()
{
	execution_trace "$AE_EXECUTE" \
		-e "$APP_OPEN" \
		"$@" \
		-e "$APP_CLOSE"
}

# tell_chrome, but presume activation state is retained for the given statements.
tell_chrome_retained ()
{
	execution_trace "$OSASCRIPT" \
		-e "$APP_OPEN" \
		"$@" \
		-e "$APP_CLOSE"

	if test $FOCUS = 'shift'
	then
		tell_chrome -e "activate"
	fi
}

# Only focus shift option.
FOCUS='retain'
while getopts "fxX" opt
do
	case "$opt" in
		f)
			# Activate browser window.
			AE_EXECUTE="$OSASCRIPT"
			FOCUS='shift'
		;;
		x)
			# Report and execute.
			execution_trace ()
			{
				(set -x; "$@")
			}
		;;
		X)
			# Report alone.
			execution_trace ()
			{
				(set -x; : "$@")
			}
		;;
		*)
			exit 1
		;;
	esac
done
shift $((OPTIND-1))

dispatch_control_operation ()
{
	local OP ARG hasarg

	OP="$1"
	shift 1

	if test $# -gt 0
	then
		ARG="$1"
		URL='"'"$(astr "$ARG")"'"'
		hasarg=':'
	else
		URL=''
		hasarg='! :'
	fi

	case "$OP" in
		agent-start)
			open -W -g -a "$CHROME_APPLICATION" -- "$@"
		;;
		agent-stop)
			tell_chrome -e "quit"
		;;

		window-new)
			# exec "$CHROME_EXECUTABLE" --new-window "$@"
			if eval $hasarg
			then
				EXECUTE_URL="set URL of $TAB_ID of $WINDOW_ID to ""$URL"
			else
				EXECUTE_URL='delay 0'
			fi

			tell_chrome \
				-e 'make new window' \
				-e "$EXECUTE_URL" \
		;;
		window-close)
			tell_chrome \
				-e 'close '"$WINDOW_ID"
		;;

		open)
			tell_chrome \
				-e "tell $WINDOW_ID to make new tab with properties "'{URL:'"$URL"'}'
		;;
		fork)
			# Get the current location and open a new tab
			URL='"'"$(astr "$(tell_chrome_retained -e "get URL of $TAB_ID of $WINDOW_ID")")"'"'
			tell_chrome \
				-e "tell $WINDOW_ID to make new tab with properties "'{URL:'"$URL"'}'
		;;
		move)
			tell_chrome \
				-e "set URL of $TAB_ID of $WINDOW_ID to ""$URL"
		;;
		re|reload)
			tell_chrome_retained \
				-e "reload $TAB_ID of $WINDOW_ID"
		;;
		location)
			# Report the location of the active tab to stdout.
			tell_chrome_retained \
				-e "get URL of $TAB_ID of $WINDOW_ID"
		;;
		close)
			tell_chrome_retained \
				-e "close $TAB_ID of $WINDOW_ID"
		;;

		*)
			# JavaScript operation or error.
			local JS
			JS="tell $TAB_ID of $WINDOW_ID to execute javascript"

			case "$OP" in
				execute)
					# Execute javascript
					JSCODE="$(echo "$ARG" | base64)"
					tell_chrome \
						-e "$JS"' "eval(atob(\"" & "'"$JSCODE"'" & "\"))"'
				;;
				home)
					tell_chrome \
						-e "$JS "'"window.home()"'
				;;
				forward)
					tell_chrome \
						-e "$JS "'"history.forward()"'
				;;
				backward)
					tell_chrome \
						-e "$JS "'"history.back()"'
				;;
				*)
					echo >&2 "ERROR: unknown command: $OP"
					echo >&2 'usage: open, move, reload, forward, backward, location, fork, close'
					exit 250
				;;
			esac
		;;
	esac
}

dispatch_control_operation "$@"
