# Functions for interacting with VirtualBox

vbox_matching_uuid() {
  pattern="$1"

  if [[ -n $pattern ]]
  then
    VBoxManage list vms | grep -F "$pattern" | sed -E 's/"(.+)" {([-0-9a-z]+)}/\2 # \1/'
  else
    VBoxManage list vms | sed -E 's/"(.+)".+/\1/'
  fi
}
