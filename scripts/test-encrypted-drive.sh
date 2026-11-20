#!/bin/bash
# Key-free checks for scripts/encrypted-drive.py, run in containers.
# No key is generated, read, or used: only CLI validation, the read-only 'info'
# command, and --dry-run paths, with a fake ssh that runs commands locally.
#
# Usage: ./scripts/test-encrypted-drive.sh
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

if [ "${1:-}" != "--inside" ]; then
    status=0
    for img in python:3.8-slim python:3.13-slim; do
        echo "########## $img"
        docker run --rm -v "$REPO:/repo:ro" "$img" bash /repo/scripts/test-encrypted-drive.sh --inside || status=1
    done
    echo "########## pyflakes"
    docker run --rm -v "$REPO:/repo:ro" python:3.13-slim sh -c \
        'pip install -q --root-user-action=ignore pyflakes >/dev/null 2>&1 && python -m pyflakes /repo/scripts/encrypted-drive.py && echo "pyflakes clean"' || status=1
    exit $status
fi

S=/repo/scripts/encrypted-drive.py
fail=0
# expect <exit-code> <description> <text the output must contain> <stdin> -- <args...>
expect() {
    local want=$1 desc=$2 needle=$3 input=$4; shift 5
    out=$(printf '%s' "$input" | python3 "$S" --ssh fakessh "$@" 2>&1); got=$?
    if [ "$got" = "$want" ] && grep -qF -- "$needle" <<<"$out"; then echo "PASS  $desc"
    else echo "FAIL  $desc (exit $got, want $want; wanted output containing: $needle)"; fail=1
         printf '      %s\n' "$out" | head -20; fi
}

echo "== $(python3 --version)"
if python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' "$S"; then echo "PASS  parses"; else fail=1; fi

# Fake host: a system NVMe disk (mounted), a NEW USB drive with an NTFS partition,
# and a USB drive that is in use. Nothing real is ever touched.
mkdir -p /shim /dev/disk/by-id
ln -sf /dev/sdz  "/dev/disk/by-id/usb-WD_Elements_FAKESERIAL1-0:0"
ln -sf /dev/sdz1 "/dev/disk/by-id/usb-WD_Elements_FAKESERIAL1-0:0-part1"
ln -sf /dev/sdy  "/dev/disk/by-id/usb-WD_Elements_BUSYSERIAL1-0:0"
cat > /shim/lsblk <<'EOF'
#!/bin/bash
cat <<'JSON'
{"blockdevices":[
 {"name":"nvme0n1","path":"/dev/nvme0n1","size":256060514304,"model":"NVMe","serial":"SYS1","tran":"nvme","type":"disk","mountpoints":[null],
  "children":[{"name":"nvme0n1p2","path":"/dev/nvme0n1p2","size":255000000000,"type":"part","fstype":"ext4","mountpoints":["/"]}]},
 {"name":"sdz","path":"/dev/sdz","size":6001175126016,"model":"WDC WD60NDZW-11C8XS1","serial":"FAKESERIAL1","tran":"usb","type":"disk","mountpoints":[null],
  "children":[{"name":"sdz1","path":"/dev/sdz1","size":6001173000000,"type":"part","fstype":"ntfs","label":"Elements","mountpoints":[null]}]},
 {"name":"sdy","path":"/dev/sdy","size":6001175126016,"model":"WDC WD60NDZW-11C8XS1","serial":"BUSYSERIAL1","tran":"usb","type":"disk","mountpoints":[null],
  "children":[{"name":"sdy1","path":"/dev/sdy1","type":"part","fstype":"crypto_LUKS","mountpoints":[null],
    "children":[{"name":"dm-WDD6T","path":"/dev/mapper/dm-WDD6T","type":"crypt","fstype":"ext4","mountpoints":["/crypt/WDD6T"]}]}]}
]}
JSON
EOF
# cryptsetup must never actually run in these tests: fail loudly if called.
# Only the read-only isLuks/luksDump are answered (with fake, key-free output, as
# real luksDump is); every other subcommand fails loudly.
cat > /shim/cryptsetup <<'EOF'
#!/bin/bash
case "$1" in
  isLuks)  [ "$2" = /dev/sdy1 ] && exit 0; exit 1 ;;
  luksDump)
    if [ "${FAKE_LUKS1:-}" = 1 ]; then
      printf 'LUKS header information for /dev/sdy1\n\nVersion:       \t1\nCipher name:   \taes\nCipher mode:   \txts-plain64\nHash spec:     \tsha256\nPayload offset:\t4096\nMK bits:       \t512\nMK digest:     \tde ad be ef\nUUID:          \t11111111-2222-3333-4444-555555555555\n\nKey Slot 0: ENABLED\n\tIterations:         \t1000\n'
    else
      printf 'LUKS header information\nVersion:       \t2\nEpoch:         \t3\nMetadata area: \t16384 [bytes]\nUUID:          \t11111111-2222-3333-4444-555555555555\n\nData segments:\n  0: crypt\n\toffset: 16777216 [bytes]\n\tlength: (whole device)\n\tcipher: aes-xts-plain64\n\tsector: 4096 [bytes]\n\nKeyslots:\n  0: luks2\n\tKey:        512 bits\n\tPriority:   normal\n\tCipher:     aes-xts-plain64\n\tCipher key: 512 bits\n\tPBKDF:      argon2id\n\tTime cost:  4\n\tMemory:     1048576\n\tSalt:       de ad be ef\n\tAF hash:    sha256\nTokens:\nDigests:\n  0: pbkdf2\n\tHash:       sha256\n\tIterations: 1000\n\tSalt:       de ad be ef\n\tDigest:     de ad be ef\n'
    fi ;;
  *) echo "cryptsetup $1 must not run in tests" >&2; exit 99 ;;
esac
EOF
cat > /shim/fakessh <<'EOF'
#!/bin/bash
while [ "$1" = "-o" ]; do shift 2; done
shift
exec bash -c "$1"
EOF
cat > /shim/sudo <<'EOF'
#!/bin/bash
[ "$1" = "-n" ] && shift
exec "$@"
EOF
chmod +x /shim/*
export PATH=/shim:$PATH

Z=00000000-0000-0000-0000-000000000000
expect 2 "argparse rejects missing subcommand" "required: cmd" "" -- --host vega
expect 1 "rejects a --name with a space" "--name may contain only" "" -- --host vega mount --name 'bad name' --partuuid $Z
expect 1 "rejects a non-UUID --partuuid" "not a UUID" "" -- --host vega mount --name OK --partuuid not-a-uuid
expect 0 "info lists disks and flags the busy one" "in use, mounted: /crypt/WDD6T" "" -- --host vega info
expect 1 "setup refuses an unknown serial" "no disk with serial 'NOPE123'" "" -- --host vega --dry-run setup --serial NOPE123 --name WDE6T
expect 1 "setup refuses the system disk" "has mounted filesystems" "" -- --host vega --dry-run setup --serial SYS1 --name X --allow-non-usb
expect 1 "setup refuses a drive that is in use" "has mounted filesystems" "" -- --host vega --dry-run setup --serial BUSYSERIAL1 --name WDE6T
expect 1 "setup aborts on a wrong confirmation" "confirmation did not match" $'WRONG\n' -- --host vega --dry-run setup --serial FAKESERIAL1 --name WDE6T
expect 0 "setup dry-run targets the new drive by its by-id path" "wipefs -a /dev/disk/by-id/usb-WD_Elements_FAKESERIAL1-0:0" $'FAKESERIAL1\n' -- --host vega --dry-run setup --serial FAKESERIAL1 --name WDE6T
expect 0 "setup dry-run wipes the old NTFS partition" "wipefs -a /dev/sdz1" $'FAKESERIAL1\n' -- --host vega --dry-run setup --serial FAKESERIAL1 --name WDE6T
expect 0 "setup dry-run sends the key only on stdin" "luksFormat --type luks2 --batch-mode '/dev/disk/by-partuuid/<partuuid>' --key-file -    <- key on stdin" $'FAKESERIAL1\n' -- --host vega --dry-run setup --serial FAKESERIAL1 --name WDE6T
expect 0 "setup dry-run prints the JSON snippet" '"partnumber": "WDC WD60NDZW-11C8XS1"' $'FAKESERIAL1\n' -- --host vega --dry-run setup --serial FAKESERIAL1 --name WDE6T
L2="luksFormat --type luks2 --cipher aes-xts-plain64 --key-size 512 --sector-size 4096 --pbkdf argon2id --hash sha256 --batch-mode"
expect 0 "--like copies a LUKS2 drive's parameters" "$L2" $'FAKESERIAL1\n' -- --host vega --dry-run setup --serial FAKESERIAL1 --name WDE6T --like /dev/sdy1 --key-env WDE6T_KEY
expect 0 "--like shows the copied parameters before confirming" "(copied from /dev/sdy1)" $'FAKESERIAL1\n' -- --host vega --dry-run setup --serial FAKESERIAL1 --name WDE6T --like /dev/sdy1
export FAKE_LUKS1=1
expect 0 "--like copies a LUKS1 drive's parameters" "luksFormat --type luks1 --cipher aes-xts-plain64 --key-size 512 --hash sha256 --batch-mode" $'FAKESERIAL1\n' -- --host vega --dry-run setup --serial FAKESERIAL1 --name WDE6T --like /dev/sdy1
unset FAKE_LUKS1
expect 1 "--like refuses a non-LUKS reference" "is not a LUKS device" $'FAKESERIAL1\n' -- --host vega --dry-run setup --serial FAKESERIAL1 --name WDE6T --like /dev/sdz1
expect 1 "--like refuses a bare word" "takes a PARTUUID or a /dev/" $'FAKESERIAL1\n' -- --host vega --dry-run setup --serial FAKESERIAL1 --name WDE6T --like WDD6T
expect 1 "--env-file requires --key-env" "--env-file needs --key-env" "" -- --host vega --dry-run setup --serial FAKESERIAL1 --name WDE6T --env-file x.env
expect 2 "--key-env and --generate are exclusive" "not allowed with argument" "" -- --host vega --dry-run setup --serial FAKESERIAL1 --name WDE6T --generate --key-env V
expect 1 "mount refuses a missing partition" "no partition with that PARTUUID" "" -- --host vega --dry-run mount --name WDE6T --partuuid $Z
expect 0 "umount dry-run prints, changes nothing" "[dry-run] vega: set -e; if mountpoint -q /crypt/WDE6T" "" -- --host vega --dry-run umount --name WDE6T

out=$(printf 'FAKESERIAL1\n' | python3 "$S" --ssh fakessh --host vega --dry-run setup --serial FAKESERIAL1 --name WDE6T 2>&1)
n=$(grep -c 'key on stdin' <<<"$out")
if [ "$n" = 3 ]; then echo "PASS  exactly 3 steps take the key (format, unlock, verify-unlock)"
else echo "FAIL  expected 3 keyed steps, got $n"; fail=1; fi
if grep -q 'not read in dry-run' <<<"$out"; then echo "FAIL  dry-run placeholder leaked into output"; fail=1
else echo "PASS  the key value never appears in output"; fi

if grep -nE 'f"[^"]*\{key\}' "$S"; then echo "FAIL  key interpolated into a string"; fail=1
else echo "PASS  key is never interpolated into a command or message"; fi

exit $fail
