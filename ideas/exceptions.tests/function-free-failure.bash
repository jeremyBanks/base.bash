eval "$(cat "$(dirname "${BASH_SOURCE[0]}")/../exceptions.bash")"

echo "hello world"

echo "hello underworld" >&2

echo "hello stdin: $(cat -)"

exit 42
