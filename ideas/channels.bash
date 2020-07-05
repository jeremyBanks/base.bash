#!/bin/bash
set -euo pipefail
shopt -s inherit_errexit compat"${BASH_COMPAT=42}"

# The timeout (in seconds) after which we raise an error when attempting to
# send, recieve, or lock a channel. Must be at least 1ms to be valid.
declare channel_timeout=0.100 && [[ $(bc <<< "$channel_timeout >= 0.001") = 1 ]]

# A pseudorandom delimiter for channel messages.
declare channel_delimiter="#$$-$BASHPID-$SHLVL-$BASH_SUBSHELL-$RANDOM-$RANDOM#"

# Creates and opens a fifo (named pipe), then unlinks it from the filesystem (so
# that only our process has access to it), storing the file descriptor in the
# named global variable.
#
# Also defines four functions, $name.{send,recv}{,-unsafe}, imitating bound 
# methods wrapping our channel-{send,recv} functions defined below.
function declare-channel {
  declare name="$1"

  declare tmp_path
  tmp_path="$(mktemp -u)"
  mkfifo "$tmp_path"
  declare fd
  exec {fd}<>"$tmp_path"
  rm "$tmp_path"

  declare -gi "${name}=${fd}"

  # "Unsafe" here refers to a lack of concurrency guarauntees -- if multiple
  # processes are both reading or both writing at the same time, the results
  # are undefined. Messages may be corrupted or lost. 
  eval "function ${name}.send-unsafe {
    # This should actually be safe as long as the message is fewer than 
    # $(ulimit -p) * 512 bytes, but measuring string byte length robustly
    # in Bash is a bit annoying due to locales, so I don't.
    channel-send \$${name} \"\$@\"
  }"
  eval "function ${name}.recv-unsafe {
    channel-recv \$${name} \"\$@\"
  }"

  # We can use filesystem locking to prevent that. This can reduce performance
  # significantly (from 2ms to 10ms on my i7-7700HQ without contention). Either 
  # way, it's extremely slow compared with other programming languages, but more
  # than adequate for my Bash needs.
  eval "function ${name}.send {
    flock --exclusive --timeout \$channel_timeout \$$name
    ${name}.send-unsafe \"\$@\"
    flock --unlock \$$name
  }"
  eval "function ${name}.recv {
    flock --exclusive --timeout \$channel_timeout \$$name
    ${name}.recv-unsafe \"\$@\"
    flock --unlock \$$name
  }"

  # Closes the file descriptor and unsets its variable and functions.
  eval "function ${name}.drop {
    eval \"exec \$${name}>&-\"
    unset ${name}
    unset -f ${name}{,.{{send,recv}{,-unsafe},drop}}
  }"
}

# Sends a message into a channel, by writing it to the specified file descriptor
# followed by the channel message delimiter.
function channel-send {
  declare -i channel_fd="$1"
  echo >&"$channel_fd" "${@:2}"
  echo >&"$channel_fd" "$channel_delimiter"
}

# Reads the next message from a channel, raising an error if none is available.
function channel-recv {
  declare -i channel_fd="$1"
  declare line
  while true; do
    if ! read -u "$channel_fd" -r -t "$channel_timeout" line; then
      echo >&2 "ERROR: read from &$channel_fd failed after ${channel_timeout}s"
      return 1
    elif [[ $line = "$channel_delimiter" ]]; then
      return 0
    else
      echo "$line"
    fi
  done
}