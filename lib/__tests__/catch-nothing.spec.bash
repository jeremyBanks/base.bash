eval "$(cat "$(dirname "${BASH_SOURCE[0]}")/../exceptions.bash")"

try
  echo hello world
catch TypeError
  echo this cannot happen
yrt

try
  echo goodbye world
catch ""
  echo this also cannot happen
yrt