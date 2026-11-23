#!/usr/bin/env bash
# Tests only the isolated Python lab VM on localhost; never a physical device.
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
lab_dir=${1:-"$project_dir/../projects/alpaca-pilot-port"}
run_name="mmt-tests-$(date +%s)"
ssh_args=(-F /dev/null -p 2223 -i "$lab_dir/state/id_ed25519" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$lab_dir/state/known_hosts" -o ConnectTimeout=8 dev@127.0.0.1)
root=/opt/benro-bundle-target
remote_dir="$root/tmp/$run_name"
ssh "${ssh_args[@]}" "test ! -e '$remote_dir' && sudo mkdir '$remote_dir'"
trap 'ssh "${ssh_args[@]}" "sudo rm -rf -- '\''$remote_dir'\''"' EXIT
tar -C "$project_dir" -cf - assets/helper test/test_manager.py test/test_pilot_adapter.py | ssh "${ssh_args[@]}" "sudo tar -xf - -C '$remote_dir'"
ssh "${ssh_args[@]}" "sudo chroot '$root' /usr/bin/env -i PATH=/opt/benro-python/bin:/bin:/usr/bin LD_LIBRARY_PATH=/opt/benro-python/lib:/lib:/usr/lib:/app/lib /opt/benro-python/bin/python3.13 -B -m unittest discover -s '/tmp/$run_name/test' -p 'test_*.py' -v"
