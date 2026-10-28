#!/bin/bash
#
# Debian 6 (squeeze) amd64 + Dotdeb PHP 5.4.45
# Self-contained rebuild for CVE-2026-109618 / CVE-2026-109619.
#
# Frozen source inputs are downloaded ONLY from:
#   https://files.zabiyaka.net/php2shell/
# SHA256SUMS on that server is the authoritative file list.
#
# The script:
#   - bootstraps gurl automatically;
#   - verifies the local source bundle using SHA256SUMS;
#   - makes rollback .debs (APT cache first, dpkg-repack fallback);
#   - installs build dependencies from Debian archive;
#   - builds 5.4.45 with the frozen security patch;
#   - verifies ABI/extensions before installation;
#   - installs only matching PHP core packages already present;
#   - automatically rolls back on install/runtime failure.
#
# IMPORTANT: automatic patching is intentionally restricted to the exact
# PHP package version 5.4.45-1~dotdeb+6.1. Other PHP 5.4.x versions are NOT upgraded
# automatically by this script.

set -u
set -o pipefail

OLDVER='5.4.45-1~dotdeb+6.1'
NEWVER="${OLDVER}+php2shell1"
STAMP="$(date +%Y%m%d-%H%M%S)"

SOURCE_BASE='https://files.zabiyaka.net/php2shell'
GURL_URL='http://files.zabiyaka.net/gurl/latest/linux/amd64/gurl'

ORIG='php5_5.4.45.orig.tar.gz'
DSC='php5_5.4.45-1~dotdeb+6.1.dsc'
DEBTAR='php5_5.4.45-1~dotdeb+6.1.debian.tar.gz'
PATCH='php-5.4.45-cve-2026-109618-109619.patch'
MANIFEST='SHA256SUMS'


BASE='/root/php54-php2shell'
WORK="$BASE/work-$STAMP"
SRCROOT="$WORK/src"
STAGE="$WORK/stage"
PKGOUT="$BASE/packages/$NEWVER"
BACKUP="/backup/php54-before-php2shell-$STAMP"

APT_LIST="$WORK/squeeze-build.list"
APT_PARTS="$WORK/apt-parts-empty"

HAS_APACHE=0
INSTALL_STARTED=0
POLICY_SAVED=0
HAD_POLICY=0

die() {
    echo
    echo "ERROR: $*"
    echo
    exit 1
}

section() {
    echo
    echo "============================================================"
    echo " $*"
    echo "============================================================"
}

fetch() {
    URL="$1"
    OUT="$2"
    N=1

    while [ "$N" -le 8 ]; do
        echo "[$N/8] $URL"
        rm -f "$OUT.tmp"

        if gurl -o "$OUT.tmp" "$URL" </dev/null; then
            if [ -s "$OUT.tmp" ]; then
                mv "$OUT.tmp" "$OUT"
                return 0
            fi
        fi

        rm -f "$OUT.tmp"
        N=$((N + 1))
        sleep 2
    done

    return 1
}

# ---------------------------------------------------------------------------
# Platform
# ---------------------------------------------------------------------------

[ "$(id -u)" = "0" ] || die "run as root"

section "PLATFORM PRECHECK"

echo "Kernel:"
uname -a
echo
echo "Debian:"
cat /etc/debian_version 2>/dev/null || true

[ "$(uname -m)" = "x86_64" ] || die "amd64/x86_64 required"
grep -q '^6\.' /etc/debian_version 2>/dev/null     || die "expected Debian 6.x (squeeze)"

mkdir -p "$WORK" "$SRCROOT" "$STAGE" "$PKGOUT" "$APT_PARTS" /backup

# ---------------------------------------------------------------------------
# Isolated archive APT configuration.
# Does not overwrite /etc/apt/sources.list.
# ---------------------------------------------------------------------------

cat > "$APT_LIST" <<'EOF'
deb http://archive.debian.org/debian squeeze main contrib non-free
deb http://archive.debian.org/debian squeeze-lts main contrib non-free
deb http://archive.debian.org/debian-security squeeze/updates main contrib non-free
EOF

APT_OPTS=(
    -o "Dir::Etc::sourcelist=$APT_LIST"
    -o "Dir::Etc::sourceparts=$APT_PARTS"
    -o "APT::Get::List-Cleanup=0"
    -o "Acquire::Check-Valid-Until=false"
)

apt_update() {
    apt-get "${APT_OPTS[@]}" update
}

apt_simulate() {
    apt-get "${APT_OPTS[@]}" -s install "$@"
}

apt_install() {
    apt-get "${APT_OPTS[@]}"         --allow-unauthenticated         --no-remove         -y install "$@"
}

# ---------------------------------------------------------------------------
# Bootstrap gurl over plain HTTP, because old TLS stacks are unreliable.
# ---------------------------------------------------------------------------

section "GURL"

if ! command -v gurl >/dev/null 2>&1; then
    echo "Installing gurl from:"
    echo "  $GURL_URL"

    if command -v curl >/dev/null 2>&1; then
        curl -fL "$GURL_URL" > /usr/local/bin/gurl             || die "could not download gurl using curl"
    elif command -v wget >/dev/null 2>&1; then
        wget -O /usr/local/bin/gurl "$GURL_URL"             || die "could not download gurl using wget"
    else
        echo "curl/wget missing; bootstrapping curl from Debian archive"
        apt_update || die "APT update failed while bootstrapping curl"
        apt_install curl || die "could not install curl"
        curl -fL "$GURL_URL" > /usr/local/bin/gurl             || die "could not download gurl"
    fi

    chmod 755 /usr/local/bin/gurl
fi

command -v gurl >/dev/null 2>&1 || die "gurl unavailable"
gurl --version 2>/dev/null || gurl -V 2>/dev/null || true

# ---------------------------------------------------------------------------
# Exact current PHP / ABI
# ---------------------------------------------------------------------------

section "CURRENT PHP"

PKGVER="$(dpkg-query -W -f='${Version}' php5-cli 2>/dev/null || true)"
echo "php5-cli package: $PKGVER"

if [ "$PKGVER" = "$NEWVER" ]; then
    echo "Already patched."
    /usr/bin/php5 -v 2>/dev/null | head -1 || true
    exit 0
fi

case "$PKGVER" in
    5.4.*) ;;
    *) die "PHP 5.4 expected; found $PKGVER" ;;
esac

[ "$PKGVER" = "$OLDVER" ] || {
    echo "Found PHP package version: $PKGVER"
    echo "This script intentionally does not migrate another PHP 5.4.x release."
    die "supported base is exactly $OLDVER"
}

[ -x /usr/bin/php5 ] || die "/usr/bin/php5 missing"

/usr/bin/php5 -v

echo
/usr/bin/php5 -n -i | grep -E '^(PHP API|PHP Extension|Zend Extension|Zend Extension Build|PHP Extension Build|Thread Safety)'

/usr/bin/php5 -n -i | grep -q '^PHP API => 20100412$'     || die "unexpected PHP API"
/usr/bin/php5 -n -i | grep -q '^PHP Extension => 20100525$'     || die "unexpected extension ABI"
/usr/bin/php5 -n -i | grep -q '^Zend Extension => 220100525$'     || die "unexpected Zend ABI"
/usr/bin/php5 -n -i | grep -q '^PHP Extension Build => API20100525,NTS$'     || die "expected PHP 5.4 NTS ABI"

if dpkg-query -W -f='${Status}' libapache2-mod-php5 2>/dev/null     | grep -q 'install ok installed'
then
    HAS_APACHE=1
    command -v apache2ctl >/dev/null 2>&1 || die "apache2ctl missing"
    apache2ctl -V 2>&1 | grep -qi 'Server MPM:.*Prefork'         || die "Apache mod_php requires Prefork here"
    apache2ctl -M 2>&1 | grep -q 'php5_module'         || die "php5_module is not loaded"
fi

# ---------------------------------------------------------------------------
# Dpkg consistency
# ---------------------------------------------------------------------------

section "DPKG AUDIT"

AUDIT="$(dpkg --audit 2>&1 || true)"
[ -z "$AUDIT" ] || {
    echo "$AUDIT"
    die "dpkg database is not clean"
}
echo "OK"

# ---------------------------------------------------------------------------
# Discover matching core packages. Third-party PHP extensions are not rebuilt.
# ---------------------------------------------------------------------------

CORE_CANDIDATES='
libapache2-mod-php5
libphp5-embed
php5
php5-cgi
php5-cli
php5-common
php5-curl
php5-dbg
php5-dev
php5-enchant
php5-gd
php5-imap
php5-interbase
php5-intl
php5-ldap
php5-mcrypt
php5-mysql
php5-odbc
php5-pgsql
php5-pspell
php5-recode
php5-snmp
php5-sqlite
php5-sybase
php5-tidy
php5-xmlrpc
php5-xsl
php-pear
'

INSTALLED_CORE=()

for P in $CORE_CANDIDATES; do
    STATUS="$(dpkg-query -W -f='${Status}' "$P" 2>/dev/null || true)"
    [ "$STATUS" = 'install ok installed' ] || continue

    V="$(dpkg-query -W -f='${Version}' "$P" 2>/dev/null || true)"
    if [ "$V" = "$OLDVER" ]; then
        INSTALLED_CORE+=("$P")
    fi
done

[ "${#INSTALLED_CORE[@]}" -gt 0 ] || die "no matching PHP core packages found"

echo "Core packages:"
printf '  %s\n' "${INSTALLED_CORE[@]}"

# ---------------------------------------------------------------------------
# Backup
# ---------------------------------------------------------------------------

section "BACKUP"

mkdir -p     "$BACKUP/configs"     "$BACKUP/runtime/usr/lib/apache2/modules"     "$BACKUP/runtime/usr/lib"     "$BACKUP/runtime/usr/bin"     "$BACKUP/rollback"     "$BACKUP/diagnostics"     "$BACKUP/logs"     "$BACKUP/source"

dpkg --get-selections > "$BACKUP/diagnostics/dpkg-selections.txt"
dpkg-query -W -f='${binary:Package}\t${Version}\t${Status}\n'     > "$BACKUP/diagnostics/packages.txt"

cp -a /etc/php5 "$BACKUP/configs/" 2>/dev/null || true
cp -a /etc/apache2 "$BACKUP/configs/" 2>/dev/null || true
cp -a /usr/lib/php5 "$BACKUP/runtime/usr/lib/" 2>/dev/null || true

if [ -f /usr/lib/apache2/modules/libphp5.so ]; then
    cp -a /usr/lib/apache2/modules/libphp5.so         "$BACKUP/runtime/usr/lib/apache2/modules/"
    sha256sum /usr/lib/apache2/modules/libphp5.so         > "$BACKUP/diagnostics/libphp5-before.sha256"
fi

for F in /usr/bin/php /usr/bin/php5 /usr/bin/php-config /usr/bin/php-config5          /usr/bin/phpize /usr/bin/phpize5
do
    if [ -e "$F" ] || [ -L "$F" ]; then
        cp -a "$F" "$BACKUP/runtime/usr/bin/" 2>/dev/null || true
    fi
done

/usr/bin/php5 -m > "$BACKUP/diagnostics/php-modules-before.txt" 2>&1
/usr/bin/php5 -i > "$BACKUP/diagnostics/php-info-before.txt" 2>&1

if [ "$HAS_APACHE" = "1" ]; then
    apache2ctl -V > "$BACKUP/diagnostics/apache-version.txt" 2>&1
    apache2ctl -M > "$BACKUP/diagnostics/apache-modules-before.txt" 2>&1
    apache2ctl -S > "$BACKUP/diagnostics/apache-vhosts-before.txt" 2>&1 || true
fi

# ---------------------------------------------------------------------------
# Install build/repack tooling first. This does not change PHP.
# ---------------------------------------------------------------------------

section "APT BUILD TOOLS"

apt_update 2>&1 | tee "$BACKUP/logs/apt-update.log"     || die "APT update failed"

BASIC=(build-essential dpkg-dev debhelper quilt fakeroot python dpkg-repack)

apt_simulate "${BASIC[@]}" > "$BACKUP/logs/apt-basic-simulate.log" 2>&1     || {
        cat "$BACKUP/logs/apt-basic-simulate.log"
        die "cannot resolve basic tools"
    }

if grep -q '^Remv ' "$BACKUP/logs/apt-basic-simulate.log"; then
    cat "$BACKUP/logs/apt-basic-simulate.log"
    die "APT wants to remove packages"
fi

apt_install "${BASIC[@]}" 2>&1 | tee "$BACKUP/logs/apt-basic-install.log"     || die "build/repack tool installation failed"

command -v dpkg-source >/dev/null 2>&1 || die "dpkg-source missing"
command -v dpkg-buildpackage >/dev/null 2>&1 || die "dpkg-buildpackage missing"
command -v dpkg-repack >/dev/null 2>&1 || die "dpkg-repack missing"

# ---------------------------------------------------------------------------
# Exact rollback .debs: cache first, otherwise repack currently installed pkg.
# ---------------------------------------------------------------------------

section "CREATE ROLLBACK PACKAGES"

ROLLBACK_DEBS=()

for P in "${INSTALLED_CORE[@]}"; do
    A="$(dpkg-query -W -f='${Architecture}' "$P")"
    FILE="${P}_${OLDVER}_${A}.deb"
    DEST="$BACKUP/rollback/$FILE"

    if [ -f "/var/cache/apt/archives/$FILE" ]; then
        echo "APT cache: $FILE"
        cp -a "/var/cache/apt/archives/$FILE" "$DEST"
    else
        echo "Repacking installed $P ..."
        mkdir -p "$WORK/repack"
        (
            cd "$WORK/repack" || exit 1
            rm -f ./*.deb
            dpkg-repack "$P"
        ) || die "dpkg-repack failed for $P"

        RF="$(find "$WORK/repack" -maxdepth 1 -type f -name '*.deb' | head -1)"
        [ -n "$RF" ] || die "repacked .deb missing for $P"

        # dpkg-repack may encode version characters in filename; validate metadata,
        # then normalize the destination filename ourselves.
        RP="$(dpkg-deb -f "$RF" Package)"
        RV="$(dpkg-deb -f "$RF" Version)"
        RA="$(dpkg-deb -f "$RF" Architecture)"

        [ "$RP" = "$P" ] || die "repacked package mismatch for $P"
        [ "$RV" = "$OLDVER" ] || die "repacked version mismatch for $P"
        [ "$RA" = "$A" ] || die "repacked architecture mismatch for $P"

        cp -a "$RF" "$DEST"
    fi

    RP="$(dpkg-deb -f "$DEST" Package)"
    RV="$(dpkg-deb -f "$DEST" Version)"
    RA="$(dpkg-deb -f "$DEST" Architecture)"

    [ "$RP" = "$P" ] || die "rollback package mismatch: $DEST"
    [ "$RV" = "$OLDVER" ] || die "rollback version mismatch: $DEST"
    [ "$RA" = "$A" ] || die "rollback arch mismatch: $DEST"

    ROLLBACK_DEBS+=("$DEST")
    echo "OK $FILE"
done

# ---------------------------------------------------------------------------
# Repair stale /usr/bin/php style alternatives, if this old host has them.
# ---------------------------------------------------------------------------

section "PHP ALTERNATIVES"

for SPEC in 'php:/usr/bin/php5' 'php-config:/usr/bin/php-config5' 'phpize:/usr/bin/phpize5'
do
    NAME="${SPEC%%:*}"
    TARGET="${SPEC#*:}"
    LINK="/usr/bin/$NAME"

    [ -e "$TARGET" ] || continue

    if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
        echo "Preserving standalone stale $LINK"
        mv "$LINK" "$LINK.before-php2shell-$STAMP"

        if update-alternatives --query "$NAME" >/dev/null 2>&1; then
            update-alternatives --set "$NAME" "$TARGET" || true
        else
            update-alternatives --install "$LINK" "$NAME" "$TARGET" 50
        fi
    fi
done

# ---------------------------------------------------------------------------
# Download frozen source bundle from our own host ONLY.
# ---------------------------------------------------------------------------

section "DOWNLOAD LOCAL SOURCE BUNDLE"

cd "$SRCROOT" || die "cannot enter source directory"

# SHA256SUMS on files.zabiyaka.net is the authoritative source-kit manifest.
# Fetch it first, then download every filename listed inside it.
fetch "$SOURCE_BASE/$MANIFEST" "$SRCROOT/$MANIFEST" \
    || die "cannot download $MANIFEST"

BUNDLE_LIST="$WORK/bundle-files.txt"

awk '
    NF >= 2 {
        name=$2
        sub(/^\*/, "", name)
        if (name != "" && name !~ /^#/)
            print name
    }
' "$SRCROOT/$MANIFEST" > "$BUNDLE_LIST"

[ -s "$BUNDLE_LIST" ] || die "$MANIFEST contains no files"

echo "Frozen source-kit files:"
cat "$BUNDLE_LIST"

while IFS= read -r FILE
do
    case "$FILE" in
        */*|..*)
            die "unsafe filename in $MANIFEST: $FILE"
            ;;
    esac

    fetch "$SOURCE_BASE/$FILE" "$SRCROOT/$FILE" \
        || die "cannot download $FILE"
done < "$BUNDLE_LIST"

section "VERIFY SHA256 BUNDLE"

(
    cd "$SRCROOT" || exit 1
    sha256sum -c "$MANIFEST"
) || die "SHA256 verification failed"

# These four files are mandatory for this particular Debian build.
for REQUIRED in "$ORIG" "$DSC" "$DEBTAR" "$PATCH"
do
    [ -s "$SRCROOT/$REQUIRED" ] \
        || die "required source-kit file missing: $REQUIRED"
done

# Also verify the two source payloads against the signed/archived Dotdeb .dsc MD5.
awk '
    /^Files:/ { f=1; next }
    f && /^[ \t]/ { print $1 "  " $3; next }
    f { exit }
' "$SRCROOT/$DSC" > "$SRCROOT/source.md5"

(
    cd "$SRCROOT" || exit 1
    md5sum -c source.md5
) || die "Dotdeb .dsc MD5 verification failed"

grep -q '^Source: php5$' "$SRCROOT/$DSC" || die "unexpected .dsc"
grep -Fq "Version: $OLDVER" "$SRCROOT/$DSC" || die "wrong .dsc version"

cp -a "$SRCROOT/$MANIFEST" "$SRCROOT/$DSC" "$SRCROOT/$PATCH"     "$BACKUP/source/"

# ---------------------------------------------------------------------------
# Extract exact Dotdeb source.
# ---------------------------------------------------------------------------

section "EXTRACT SOURCE"

dpkg-source -x "$SRCROOT/$DSC"     2>&1 | tee "$BACKUP/logs/dpkg-source.log"     || die "dpkg-source failed"

SRCDIR="$(find "$SRCROOT" -maxdepth 1 -type d -name 'php5-5.4.45*' | head -1)"
[ -n "$SRCDIR" ] || die "source directory not found"

cd "$SRCDIR" || die

# ---------------------------------------------------------------------------
# Avoid pulling a local MySQL server just to run package tests.
# Build uses nocheck.
# ---------------------------------------------------------------------------

section "NORMALIZE BUILD DEPENDENCIES"

python <<'PY'
import re

path = 'debian/control'
lines = open(path).read().splitlines(True)
out = []
i = 0

while i < len(lines):
    line = lines[i]

    if line.startswith('Build-Depends:') or line.startswith('Build-Depends-Indep:'):
        key, first = line.split(':', 1)
        value = first.strip()
        i += 1

        while i < len(lines) and (lines[i].startswith(' ') or lines[i].startswith('\t')):
            value += ' ' + lines[i].strip()
            i += 1

        kept = []
        for clause in value.split(','):
            names = []
            for alt in clause.split('|'):
                name = re.sub(r'\([^)]*\)', '', alt)
                name = re.sub(r'\[[^\]]*\]', '', name).strip()
                name = name.split(':', 1)[0].strip()
                names.append(name)

            if 'mysql-server' in names or 'virtual-mysql-server' in names:
                continue

            if clause.strip():
                kept.append(clause.strip())

        out.append('%s: %s\n' % (key, ', '.join(kept)))
        continue

    out.append(line)
    i += 1

open(path, 'w').writelines(out)
PY

grep -n 'mysql-server\|virtual-mysql-server' debian/control     && die "mysql-server build dependency remains"     || true

# ---------------------------------------------------------------------------
# Resolve Debian build dependencies.
# ---------------------------------------------------------------------------

python <<'PY' > "$WORK/build-deps.txt"
import re
import subprocess
import sys

text = open('debian/control').read()
source = text.split('\n\n', 1)[0]

fields = {}
current = None

for line in source.splitlines():
    if line.startswith(' ') or line.startswith('\t'):
        if current:
            fields[current] += ' ' + line.strip()
        continue

    if ':' in line:
        key, value = line.split(':', 1)
        current = key.strip()
        fields[current] = value.strip()

relations = []
for key in ('Build-Depends', 'Build-Depends-Indep'):
    if fields.get(key):
        relations.extend(fields[key].split(','))

def available(pkg):
    p = subprocess.Popen(
        ['apt-cache', 'show', pkg],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    out, err = p.communicate()
    return re.search(r'(?m)^Package:\s*' + re.escape(pkg) + r'\s*$', out) is not None

def providers(pkg):
    """
    Resolve old Debian virtual packages via apt-cache showpkg.
    Example: libc-client-dev -> libc-client2007e-dev.
    """
    p = subprocess.Popen(
        ['apt-cache', 'showpkg', pkg],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    out, err = p.communicate()

    result = []
    in_reverse_provides = False

    for line in out.splitlines():
        if line.strip() == 'Reverse Provides:':
            in_reverse_provides = True
            continue

        if not in_reverse_provides:
            continue

        if not line.strip():
            continue

        # A new apt-cache section means Reverse Provides ended.
        if line.endswith(':') and not line.startswith(' '):
            break

        name = line.strip().split()[0]
        if name and name not in result and available(name):
            result.append(name)

    return result

chosen = []

for relation in relations:
    relation = relation.strip()
    if not relation:
        continue

    selected = None

    for alt in relation.split('|'):
        alt = re.sub(r'\([^)]*\)', '', alt)
        alt = re.sub(r'\[[^\]]*\]', '', alt).strip()
        if not alt:
            continue

        pkg = alt.split(':', 1)[0].strip()

        if available(pkg):
            selected = pkg
            break

        # Old Debian Build-Depends often name virtual packages.
        # If so, install one real package that Provides: it.
        virtual_providers = providers(pkg)
        if virtual_providers:
            selected = virtual_providers[0]
            sys.stderr.write(
                'Virtual build dependency %s -> %s\n'
                % (pkg, selected)
            )
            break

    if selected is None:
        sys.stderr.write('Cannot resolve build dependency: %s\n' % relation)
        sys.exit(2)

    if selected not in chosen:
        chosen.append(selected)

for pkg in chosen:
    print(pkg)
PY

[ "$?" = "0" ] || die "could not resolve build dependencies"

BUILD_DEPS=()
while read P; do
    [ -n "$P" ] && BUILD_DEPS+=("$P")
done < "$WORK/build-deps.txt"

echo "Build dependencies:"
printf '  %s\n' "${BUILD_DEPS[@]}"

echo
echo "APT candidates for version-sensitive build dependencies:"
for P in \
    apache2-prefork-dev apache2.2-common \
    libcurl4-openssl-dev libcurl3 \
    libexpat1-dev libexpat1 \
    libfreetype6-dev libfreetype6 \
    libgcrypt11-dev libgcrypt11 \
    libldap2-dev libldap-2.4-2 \
    libmagic-dev libmagic1 \
    libmysqlclient-dev libmysqlclient16 \
    libpq-dev libpq5 \
    libssl-dev libssl0.9.8 \
    libxml2-dev libxml2
do
    apt-cache policy "$P" 2>/dev/null | sed -n '1,8p'
done | tee "$BACKUP/logs/apt-builddeps-policy.log"

apt_simulate "${BUILD_DEPS[@]}" > "$BACKUP/logs/apt-builddeps-simulate.log" 2>&1     || {
        cat "$BACKUP/logs/apt-builddeps-simulate.log"
        die "build dependency simulation failed"
    }

if grep -q '^Remv ' "$BACKUP/logs/apt-builddeps-simulate.log"; then
    cat "$BACKUP/logs/apt-builddeps-simulate.log"
    die "APT wants to remove packages"
fi

apt_install "${BUILD_DEPS[@]}" 2>&1 | tee "$BACKUP/logs/apt-builddeps-install.log"     || die "build dependency installation failed"

dpkg-checkbuilddeps > "$BACKUP/logs/dpkg-checkbuilddeps.log" 2>&1     || {
        cat "$BACKUP/logs/dpkg-checkbuilddeps.log"
        die "build dependencies remain unsatisfied"
    }

# ---------------------------------------------------------------------------
# Frozen patch from our own host.
# ---------------------------------------------------------------------------

section "SECURITY PATCH"

PATCHFILE="$SRCROOT/$PATCH"
FILTERED_PATCH="$WORK/php2shell-without-zend-operators.patch"
OPERATORS_META="$WORK/zend-operators.meta"

grep -q 'max_multipart_body_parts' "$PATCHFILE" \
    || die "unexpected patch: multipart protection missing"
grep -q 'zend_mm_safe_error_ex' "$PATCHFILE" \
    || die "unexpected patch: safe OOM protection missing"

# Dotdeb's already-patched PHP 5.4 source differs slightly from vanilla
# PHP 5.4.45 in Zend/zend_operators.c.  The upstream backport changes only
# the four exact "String size overflow" fatal paths in this file.  Instead
# of allowing fuzzy patching, remove that one file from the generic patch,
# verify its intended changes, and apply the equivalent exact replacements
# through a separate quilt patch.
python - "$PATCHFILE" "$FILTERED_PATCH" "$OPERATORS_META" <<'PY'
import sys

src, dst, meta = sys.argv[1:4]
lines = open(src, 'r').readlines()

sections = []
preamble = []
current = None

for line in lines:
    if line.startswith('diff '):
        if current is not None:
            sections.append(current)
        current = [line]
    else:
        if current is None:
            preamble.append(line)
        else:
            current.append(line)

if current is not None:
    sections.append(current)

target = []
kept = []

for section in sections:
    header = section[0]
    if 'Zend/zend_operators.c' in header:
        target.append(section)
    else:
        kept.append(section)

if len(target) != 1:
    sys.stderr.write(
        'Expected exactly one Zend/zend_operators.c diff section, found %d\n'
        % len(target)
    )
    sys.exit(2)

target = target[0]

old_stmt = 'zend_error(E_ERROR, "String size overflow");'
new_stmt = 'zend_mm_safe_error_ex("String size overflow");'

removed = 0
added = 0

for line in target:
    if line.startswith('---') or line.startswith('+++'):
        continue

    if line.startswith('-'):
        body = line[1:].strip()
        if body != old_stmt:
            sys.stderr.write(
                'Unexpected removed line in Zend/zend_operators.c patch:\n%s'
                % line
            )
            sys.exit(3)
        removed += 1

    elif line.startswith('+'):
        body = line[1:].strip()
        if body != new_stmt:
            sys.stderr.write(
                'Unexpected added line in Zend/zend_operators.c patch:\n%s'
                % line
            )
            sys.exit(4)
        added += 1

if removed == 0 or removed != added:
    sys.stderr.write(
        'Unexpected zend_operators change count: removed=%d added=%d\n'
        % (removed, added)
    )
    sys.exit(5)

with open(dst, 'w') as f:
    f.writelines(preamble)
    for section in kept:
        f.writelines(section)

with open(meta, 'w') as f:
    f.write('PATCH_EXPECTED=%d\n' % removed)

print('Zend/zend_operators.c exact replacements expected: %d' % removed)
PY

[ "$?" = "0" ] || die "could not safely split Zend/zend_operators.c from patch"

. "$OPERATORS_META"

[ "$PATCH_EXPECTED" -gt 0 ] || die "invalid zend_operators patch count"

# The axon003 PHP 5.4.45 v2 patch was prepared against the Remi EL7 tree,
# where this section contains four overflow paths.  Stock PHP 5.4.45, and
# the Dotdeb 5.4.45 tree extracted here, contain only the two concat_function()
# paths.  Those are the only two exact statements that must be converted here.
DOTDEB_EXPECTED=2

ACTUAL="$(
python <<'PY'
path = 'Zend/zend_operators.c'
needle = 'zend_error(E_ERROR, "String size overflow");'
text = open(path, 'r').read()
print(text.count(needle))
PY
)"

echo "Zend/zend_operators.c String-size-overflow audit:"
echo "  paths represented by upstream/Remi patch: $PATCH_EXPECTED"
echo "  paths expected in Dotdeb PHP 5.4.45:     $DOTDEB_EXPECTED"
echo "  paths present in extracted Dotdeb tree:  $ACTUAL"

[ "$PATCH_EXPECTED" -ge "$DOTDEB_EXPECTED" ] \
    || die "security patch does not cover the Dotdeb overflow paths"

if [ "$ACTUAL" != "$DOTDEB_EXPECTED" ]; then
    echo
    echo "Matching lines in Dotdeb source:"
    grep -n 'String size overflow' Zend/zend_operators.c || true
    die "unexpected Zend/zend_operators.c layout for Dotdeb PHP 5.4.45"
fi

section "PATCH DRY RUN (ALL OTHER FILES)"

patch --dry-run -p1 < "$FILTERED_PATCH" \
    > "$BACKUP/logs/patch-dry-run.log" 2>&1 \
    || {
        cat "$BACKUP/logs/patch-dry-run.log"
        die "security patch has conflicts outside Zend/zend_operators.c"
    }

cat "$BACKUP/logs/patch-dry-run.log"

section "APPLY SECURITY PATCH"

mkdir -p debian/patches

CORE_PATCH='9999-php2shell-cve-2026-core.patch'
OPERATORS_PATCH='9999-php2shell-cve-2026-zend-operators.patch'

cp -a "$FILTERED_PATCH" "debian/patches/$CORE_PATCH"
[ -f debian/patches/series ] || : > debian/patches/series

grep -q "^$CORE_PATCH" debian/patches/series \
    || echo "$CORE_PATCH -p1" >> debian/patches/series

export QUILT_PATCHES=debian/patches

quilt push -a 2>&1 | tee "$BACKUP/logs/quilt-core.log" \
    || die "quilt failed applying PHP2Shell core patch"

# Create a separate deterministic quilt patch for the Dotdeb-specific
# zend_operators.c layout.
quilt new "$OPERATORS_PATCH" \
    2>&1 | tee "$BACKUP/logs/quilt-operators-new.log" \
    || die "cannot create zend_operators quilt patch"

quilt add Zend/zend_operators.c \
    || die "cannot add Zend/zend_operators.c to quilt patch"

python - "$DOTDEB_EXPECTED" <<'PY'
import sys

expected = int(sys.argv[1])
path = 'Zend/zend_operators.c'
old = 'zend_error(E_ERROR, "String size overflow");'
new = 'zend_mm_safe_error_ex("String size overflow");'

text = open(path, 'r').read()
count = text.count(old)

if count != expected:
    sys.stderr.write(
        'Refusing replacement: expected %d exact statements, found %d\n'
        % (expected, count)
    )
    sys.exit(2)

text = text.replace(old, new)

if old in text:
    sys.stderr.write('Old String size overflow fatal path remains\n')
    sys.exit(3)

open(path, 'w').write(text)
print('Replaced %d exact String size overflow fatal paths' % count)
PY

[ "$?" = "0" ] || die "failed to adapt Zend/zend_operators.c safely"

quilt refresh \
    2>&1 | tee "$BACKUP/logs/quilt-operators-refresh.log" \
    || die "cannot refresh zend_operators quilt patch"

# Final source-level assertions.
grep -q 'zend_mm_safe_error_ex("String size overflow")' Zend/zend_operators.c \
    || die "safe String size overflow handler missing"

if grep -q 'zend_error(E_ERROR, "String size overflow")' Zend/zend_operators.c; then
    die "unsafe String size overflow handler still present"
fi

echo
echo "Security patch applied successfully, including Dotdeb zend_operators adaptation."
# ---------------------------------------------------------------------------
# New local package version.
# ---------------------------------------------------------------------------

section "PACKAGE VERSION"

{
    echo "php5 ($NEWVER) squeeze; urgency=high"
    echo
    echo "  * Local security rebuild for CVE-2026-109618 and CVE-2026-109619."
    echo
    echo " -- Local Security Build <root@localhost>  $(date -R)"
    echo
    cat debian/changelog
} > "$WORK/changelog.new"

mv "$WORK/changelog.new" debian/changelog

PARSED_VERSION="$(
    dpkg-parsechangelog 2>/dev/null         | sed -n 's/^Version:[[:space:]]*//p'         | head -1
)"

[ "$PARSED_VERSION" = "$NEWVER" ]     || die "failed to set new package version (got: $PARSED_VERSION)"

# ---------------------------------------------------------------------------
# Build.
# ---------------------------------------------------------------------------

section "BUILD"

export DEB_BUILD_OPTIONS='nocheck parallel=2'

dpkg-buildpackage -b -uc -us 2>&1 | tee "$BACKUP/logs/php54-build.log"
BUILD_RC=${PIPESTATUS[0]}
[ "$BUILD_RC" = "0" ] || die "PHP build failed"

# ---------------------------------------------------------------------------
# Verify only packages corresponding to what was installed before.
# ---------------------------------------------------------------------------

section "VERIFY BUILT PACKAGES"

NEW_DEBS=()

for P in "${INSTALLED_CORE[@]}"; do
    A="$(dpkg-query -W -f='${Architecture}' "$P")"
    F="$(find "$SRCROOT" -maxdepth 1 -type f         -name "${P}_${NEWVER}_${A}.deb" | head -1)"

    [ -n "$F" ] || die "built package missing: $P ($A)"

    [ "$(dpkg-deb -f "$F" Package)" = "$P" ] || die "package mismatch: $F"
    [ "$(dpkg-deb -f "$F" Version)" = "$NEWVER" ] || die "version mismatch: $F"
    [ "$(dpkg-deb -f "$F" Architecture)" = "$A" ] || die "arch mismatch: $F"

    NEW_DEBS+=("$F")
    cp -a "$F" "$PKGOUT/"
    echo "OK $(basename "$F")"
done

cp -a "$SRCROOT/$PATCH" "$SRCROOT/$MANIFEST" "$PKGOUT/"

# ---------------------------------------------------------------------------
# Offline ABI/runtime test with current extension configuration.
# ---------------------------------------------------------------------------

section "OFFLINE TEST"

rm -rf "$STAGE"
mkdir -p "$STAGE"

for F in "${NEW_DEBS[@]}"; do
    dpkg-deb -x "$F" "$STAGE" || die "cannot extract $F"
done

NEWPHP="$STAGE/usr/bin/php5"
[ -x "$NEWPHP" ] || die "new php5 binary missing"

"$NEWPHP" -n -v || die "new PHP cannot start"
"$NEWPHP" -n -i > "$BACKUP/diagnostics/new-php-info.txt"

grep -q '^PHP API => 20100412$' "$BACKUP/diagnostics/new-php-info.txt"     || die "PHP API changed"
grep -q '^PHP Extension => 20100525$' "$BACKUP/diagnostics/new-php-info.txt"     || die "PHP extension ABI changed"
grep -q '^Zend Extension => 220100525$' "$BACKUP/diagnostics/new-php-info.txt"     || die "Zend ABI changed"
grep -q '^PHP Extension Build => API20100525,NTS$' "$BACKUP/diagnostics/new-php-info.txt"     || die "unexpected PHP build ABI"

ldd "$NEWPHP" > "$BACKUP/diagnostics/new-php-ldd.txt"
grep -q 'not found' "$BACKUP/diagnostics/new-php-ldd.txt"     && die "new PHP has unresolved libraries"

if [ "$HAS_APACHE" = "1" ]; then
    NEWLIB="$STAGE/usr/lib/apache2/modules/libphp5.so"
    [ -f "$NEWLIB" ] || die "new libphp5.so missing"
    ldd "$NEWLIB" > "$BACKUP/diagnostics/new-libphp5-ldd.txt"
    grep -q 'not found' "$BACKUP/diagnostics/new-libphp5-ldd.txt"         && die "new libphp5.so has unresolved libraries"
fi

"$NEWPHP"     -c /etc/php5/cli/php.ini     -d display_errors=1     -d display_startup_errors=1     -m     > "$BACKUP/diagnostics/new-php-modules.txt"     2> "$BACKUP/diagnostics/new-php-startup-errors.txt"

if grep -Ei 'PHP Startup|Unable to load|undefined symbol|cannot open shared object|segmentation|segfault' "$BACKUP/diagnostics/new-php-startup-errors.txt"
then
    cat "$BACKUP/diagnostics/new-php-startup-errors.txt"
    die "existing PHP extensions are incompatible with rebuilt PHP"
fi

"$NEWPHP" -n -r '
$v = ini_get("max_multipart_body_parts");
if ($v === false) exit(1);
echo "max_multipart_body_parts=", $v, "\n";
' || die "security patch signal missing"

# ---------------------------------------------------------------------------
# Service restart blocker / rollback.
# ---------------------------------------------------------------------------

save_policy() {
    [ "$POLICY_SAVED" = "0" ] || return 0
    POLICY_SAVED=1

    if [ -e /usr/sbin/policy-rc.d ]; then
        HAD_POLICY=1
        cp -a /usr/sbin/policy-rc.d "$BACKUP/policy-rc.d.original"
    fi
}

block_services() {
    save_policy
    cat > /usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF
    chmod 755 /usr/sbin/policy-rc.d
}

restore_policy() {
    [ "$POLICY_SAVED" = "1" ] || return 0

    if [ "$HAD_POLICY" = "1" ]; then
        cp -a "$BACKUP/policy-rc.d.original" /usr/sbin/policy-rc.d
    else
        rm -f /usr/sbin/policy-rc.d
    fi
}

rollback() {
    echo
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo " INSTALL FAILED -- ROLLING BACK"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"

    block_services

    if [ "$HAS_APACHE" = "1" ]; then
        /etc/init.d/apache2 stop || true
    fi

    dpkg -i "${ROLLBACK_DEBS[@]}" || true

    if [ -d "$BACKUP/runtime/usr/lib/php5" ]; then
        rm -rf /usr/lib/php5
        cp -a "$BACKUP/runtime/usr/lib/php5" /usr/lib/
    fi

    if [ -f "$BACKUP/runtime/usr/lib/apache2/modules/libphp5.so" ]; then
        cp -a "$BACKUP/runtime/usr/lib/apache2/modules/libphp5.so"             /usr/lib/apache2/modules/libphp5.so
    fi

    if [ -d "$BACKUP/configs/php5" ]; then
        rm -rf /etc/php5
        cp -a "$BACKUP/configs/php5" /etc/php5
    fi

    restore_policy

    if [ "$HAS_APACHE" = "1" ]; then
        apache2ctl configtest || true
        /etc/init.d/apache2 start || true
    fi

    echo
    echo "Rollback PHP:"
    /usr/bin/php5 -v || true
    echo "Backup: $BACKUP"
    exit 1
}

signal_handler() {
    if [ "$INSTALL_STARTED" = "1" ]; then
        rollback
    fi
    restore_policy
    exit 130
}

trap signal_handler INT TERM

# ---------------------------------------------------------------------------
# Install.
# ---------------------------------------------------------------------------

section "INSTALL PATCHED PACKAGES"

if [ "$HAS_APACHE" = "1" ]; then
    apache2ctl configtest || die "Apache config invalid before install"
fi

block_services
INSTALL_STARTED=1

dpkg -i "${NEW_DEBS[@]}" || rollback

for P in "${INSTALLED_CORE[@]}"; do
    V="$(dpkg-query -W -f='${Version}' "$P" 2>/dev/null || true)"
    echo "$P    $V"
    [ "$V" = "$NEWVER" ] || rollback
done

/usr/bin/php5 -v || rollback
/usr/bin/php5 -v 2>&1 | head -1 | grep -Fq "$NEWVER" || rollback

/usr/bin/php5 -m     > "$BACKUP/diagnostics/php-modules-after.txt"     2> "$BACKUP/diagnostics/php-startup-after.txt"     || rollback

if grep -Ei 'PHP Startup|Unable to load|undefined symbol|cannot open shared object|segmentation|segfault' "$BACKUP/diagnostics/php-startup-after.txt"
then
    cat "$BACKUP/diagnostics/php-startup-after.txt"
    rollback
fi

/usr/bin/php5 -r '
$v = ini_get("max_multipart_body_parts");
if ($v === false) exit(1);
echo "max_multipart_body_parts=", $v, "\n";
' || rollback

if [ "$HAS_APACHE" = "1" ]; then
    apache2ctl configtest || rollback
fi

restore_policy

if [ "$HAS_APACHE" = "1" ]; then
    section "RESTART APACHE"
    /etc/init.d/apache2 restart || rollback
    sleep 2

    ps aux | grep '[a]pache2' >/dev/null || rollback

    apache2ctl -M > "$BACKUP/diagnostics/apache-modules-after.txt" 2>&1         || rollback

    grep -q 'mpm_prefork_module' "$BACKUP/diagnostics/apache-modules-after.txt"         || rollback
    grep -q 'php5_module' "$BACKUP/diagnostics/apache-modules-after.txt"         || rollback
fi

INSTALL_STARTED=0

# ---------------------------------------------------------------------------
# Final state + backup archive.
# ---------------------------------------------------------------------------

section "FINAL STATE"

/usr/bin/php5 -v

echo
/usr/bin/php5 -r '
echo "max_multipart_body_parts=",
     ini_get("max_multipart_body_parts"),
     "\n";
'

echo
echo "Patched packages:"
for P in "${INSTALLED_CORE[@]}"; do
    dpkg-query -W -f='${binary:Package}\t${Version}\t${Status}\n' "$P"
done

section "ARCHIVE BACKUP"

tar czpf "$BACKUP.tar.gz" -C /backup "$(basename "$BACKUP")"     || echo "WARNING: backup directory exists, tar.gz creation failed"

if [ -f "$BACKUP.tar.gz" ]; then
    sha256sum "$BACKUP.tar.gz" > "$BACKUP.tar.gz.sha256"
fi

section "PHP 5.4 PHP2SHELL UPDATE SUCCESSFUL"

echo
/usr/bin/php5 -v | head -1
echo
echo "Built packages: $PKGOUT"
echo "Backup:         $BACKUP"
echo "Archive:        $BACKUP.tar.gz"
echo
echo "DO NOT DELETE THE BACKUP."
