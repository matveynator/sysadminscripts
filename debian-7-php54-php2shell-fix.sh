#!/bin/bash
#
# Debian 7 (Wheezy) amd64 + Dotdeb PHP 5.4.45
# Local rebuild with unofficial backport for CVE-2026-109618 / CVE-2026-109619.
#
# Safe behaviour:
#   * installs gurl automatically if absent;
#   * uses isolated Wheezy/Dotdeb APT sources for build dependencies;
#   * backs up PHP/Apache and collects exact rollback .debs;
#   * downloads the exact Dotdeb 5.4.45 source;
#   * downloads the PHP 5.4.45 security backport and dry-runs it first;
#   * rebuilds packages without changing PHP ABI;
#   * tests current extensions against the new binary;
#   * installs only PHP core packages that were already installed;
#   * rolls back automatically if installation/runtime checks fail.
#
# IMPORTANT:
#   This script intentionally supports only:
#     Debian 7.x, amd64, PHP 5.4.45-1~dotdeb+7.1, NTS.
#   If another PHP 5.4.x build is found, it exits WITHOUT changing PHP.
#

set -u
set -o pipefail

OLDVER='5.4.45-1~dotdeb+7.1'
NEWVER="${OLDVER}+php2shell1"
STAMP="$(date +%Y%m%d-%H%M%S)"

BASE='/root/php54-php2shell'
WORK="$BASE/work-$STAMP"
SRCROOT="$WORK/src"
STAGE="$WORK/stage"
PKGOUT="$BASE/packages/$NEWVER"
BACKUP="/backup/php54-before-php2shell-$STAMP"

GURL_URL='http://files.zabiyaka.net/gurl/latest/linux/amd64/gurl'
DOTDEB_POOL='https://mirrors.nju.edu.cn/dotdeb/pool/all/p/php5'
DSCNAME="php5_${OLDVER}.dsc"

PATCH_REPO='axon003/php-legacy-cve-2026-109618'
PATCH_NAME='php-5.4.45-cve-2026-109618-109619.patch'

APT_LIST="$WORK/wheezy-build.list"
APT_PARTS="$WORK/apt-parts-empty"

INSTALL_STARTED=0
POLICY_SAVED=0
HAD_POLICY=0

die()
{
    echo
    echo "ERROR: $*"
    echo
    exit 1
}

section()
{
    echo
    echo "============================================================"
    echo " $*"
    echo "============================================================"
}

# ----- platform -------------------------------------------------------------

[ "$(id -u)" = "0" ] || die "run as root"

section "PLATFORM PRECHECK"

echo "Kernel:"
uname -a

echo
echo "Debian:"
cat /etc/debian_version 2>/dev/null || true

[ "$(uname -m)" = "x86_64" ] || die "this script supports amd64 only"
grep -q '^7\.' /etc/debian_version 2>/dev/null || die "expected Debian 7.x Wheezy"

mkdir -p "$WORK" "$SRCROOT" "$STAGE" "$PKGOUT" "$APT_PARTS" /backup

# ----- isolated APT sources -------------------------------------------------

cat > "$APT_LIST" <<'EOF'
deb http://archive.debian.org/debian wheezy main contrib non-free
deb http://archive.debian.org/debian-security wheezy/updates main contrib non-free
deb http://mirrors.aliyun.com/dotdeb/packages.dotdeb.org wheezy all
deb-src http://mirrors.aliyun.com/dotdeb/packages.dotdeb.org wheezy all
EOF

APT_OPTS=(
    -o "Dir::Etc::sourcelist=$APT_LIST"
    -o "Dir::Etc::sourceparts=$APT_PARTS"
    -o "APT::Get::List-Cleanup=0"
    -o "Acquire::Check-Valid-Until=false"
)

apt_update()
{
    apt-get "${APT_OPTS[@]}" update
}

apt_simulate()
{
    apt-get "${APT_OPTS[@]}" -s install "$@"
}

apt_install()
{
    apt-get "${APT_OPTS[@]}" \
        --allow-unauthenticated \
        --no-remove \
        -y install "$@"
}

# ----- gurl bootstrap -------------------------------------------------------

section "GURL"

if ! command -v gurl >/dev/null 2>&1; then
    echo "gurl not found; installing $GURL_URL"

    if command -v curl >/dev/null 2>&1; then
        curl -fL "$GURL_URL" > /usr/local/bin/gurl \
            || die "could not download gurl with curl"
    elif command -v wget >/dev/null 2>&1; then
        wget -O /usr/local/bin/gurl "$GURL_URL" \
            || die "could not download gurl with wget"
    else
        echo "Neither curl nor wget exists. Installing curl from Wheezy archive..."
        apt_update || die "APT update failed while bootstrapping curl"
        apt_install curl || die "could not install curl"
        curl -fL "$GURL_URL" > /usr/local/bin/gurl \
            || die "could not download gurl"
    fi

    chmod 755 /usr/local/bin/gurl
fi

command -v gurl || die "gurl is still unavailable"
gurl --version 2>/dev/null || gurl -V 2>/dev/null || true

# ----- current PHP ----------------------------------------------------------

section "CURRENT PHP"

command -v dpkg-query >/dev/null 2>&1 || die "dpkg-query missing"

PKGVER="$(dpkg-query -W -f='${Version}' php5-cli 2>/dev/null || true)"

echo "php5-cli package: $PKGVER"

if [ "$PKGVER" = "$NEWVER" ]; then
    echo
    echo "Already patched:"
    /usr/bin/php5 -v 2>/dev/null | head -1 || true
    exit 0
fi

case "$PKGVER" in
    5.4.*)
        ;;
    *)
        die "expected PHP 5.4 package, found: $PKGVER"
        ;;
esac

[ "$PKGVER" = "$OLDVER" ] || {
    echo
    echo "This host has PHP $PKGVER."
    echo "The security patch used here is specifically for PHP 5.4.45."
    echo "Refusing an automatic PHP-version migration."
    die "supported base is exactly $OLDVER"
}

[ -x /usr/bin/php5 ] || die "/usr/bin/php5 missing"

/usr/bin/php5 -v

echo
echo "ABI:"
/usr/bin/php5 -n -i | grep -E \
'^(PHP API|PHP Extension|Zend Extension|Zend Extension Build|PHP Extension Build|Thread Safety)'

/usr/bin/php5 -n -i | grep -q '^PHP API => 20100412$' \
    || die "unexpected PHP API"
/usr/bin/php5 -n -i | grep -q '^PHP Extension => 20100525$' \
    || die "unexpected PHP extension ABI"
/usr/bin/php5 -n -i | grep -q '^Zend Extension => 220100525$' \
    || die "unexpected Zend ABI"
/usr/bin/php5 -n -i | grep -q '^PHP Extension Build => API20100525,NTS$' \
    || die "expected NTS PHP 5.4 ABI"

# ----- Apache check, if mod_php is installed --------------------------------

HAS_APACHE=0
if dpkg-query -W -f='${Status}' libapache2-mod-php5 2>/dev/null \
    | grep -q 'install ok installed'
then
    HAS_APACHE=1

    command -v apache2ctl >/dev/null 2>&1 || die "apache2ctl missing"
    apache2ctl -V 2>&1 | grep -qi 'Server MPM:.*Prefork' \
        || die "mod_php host is not using Prefork"
    apache2ctl -M 2>&1 | grep -q 'php5_module' \
        || die "php5_module is not loaded"
fi

# ----- clean dpkg state -----------------------------------------------------

section "DPKG AUDIT"

AUDIT="$(dpkg --audit 2>&1 || true)"
[ -z "$AUDIT" ] || {
    echo "$AUDIT"
    die "dpkg database is not clean"
}
echo "OK"

# ----- discover installed PHP-core packages --------------------------------

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

for P in $CORE_CANDIDATES
do
    STATUS="$(dpkg-query -W -f='${Status}' "$P" 2>/dev/null || true)"
    [ "$STATUS" = 'install ok installed' ] || continue

    V="$(dpkg-query -W -f='${Version}' "$P" 2>/dev/null || true)"

    # Only packages from the exact PHP source-package version are replaced.
    if [ "$V" = "$OLDVER" ]; then
        INSTALLED_CORE+=("$P")
    fi
done

[ "${#INSTALLED_CORE[@]}" -gt 0 ] || die "no matching PHP core packages found"

echo "Core packages to rebuild/install:"
printf '  %s\n' "${INSTALLED_CORE[@]}"

# ----- backup ---------------------------------------------------------------

section "BACKUP"

mkdir -p \
    "$BACKUP/configs" \
    "$BACKUP/runtime/usr/lib/apache2/modules" \
    "$BACKUP/runtime/usr/lib" \
    "$BACKUP/runtime/usr/bin" \
    "$BACKUP/rollback" \
    "$BACKUP/diagnostics" \
    "$BACKUP/logs" \
    "$BACKUP/source"

dpkg --get-selections > "$BACKUP/diagnostics/dpkg-selections.txt"

dpkg-query -W -f='${binary:Package}\t${Version}\t${Status}\n' \
    > "$BACKUP/diagnostics/packages.txt"

cp -a /etc/php5 "$BACKUP/configs/" 2>/dev/null || true
cp -a /etc/apache2 "$BACKUP/configs/" 2>/dev/null || true

cp -a /usr/lib/php5 "$BACKUP/runtime/usr/lib/" 2>/dev/null || true

if [ -f /usr/lib/apache2/modules/libphp5.so ]; then
    cp -a /usr/lib/apache2/modules/libphp5.so \
        "$BACKUP/runtime/usr/lib/apache2/modules/"
    sha256sum /usr/lib/apache2/modules/libphp5.so \
        > "$BACKUP/diagnostics/libphp5-before.sha256"
fi

for F in /usr/bin/php /usr/bin/php5 /usr/bin/php-config /usr/bin/php-config5 \
         /usr/bin/phpize /usr/bin/phpize5
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

# ----- generic downloader ---------------------------------------------------

fetch()
{
    URL="$1"
    OUT="$2"
    N=1

    while [ "$N" -le 8 ]
    do
        echo "[$N/8] $URL"
        rm -f "$OUT.tmp"

        if gurl -o "$OUT.tmp" "$URL"; then
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

# ----- rollback packages ----------------------------------------------------

section "COLLECT EXACT ROLLBACK .DEBS"

ROLLBACK_DEBS=()

for P in "${INSTALLED_CORE[@]}"
do
    A="$(dpkg-query -W -f='${Architecture}' "$P")"
    FILE="${P}_${OLDVER}_${A}.deb"
    FOUND=''

    if [ -f "/var/cache/apt/archives/$FILE" ]; then
        FOUND="/var/cache/apt/archives/$FILE"
    else
        echo "Not in APT cache: $FILE"
        fetch "$DOTDEB_POOL/$FILE" "$BACKUP/rollback/$FILE" \
            || die "could not obtain rollback package $FILE"
        FOUND="$BACKUP/rollback/$FILE"
    fi

    if [ "$FOUND" != "$BACKUP/rollback/$FILE" ]; then
        cp -a "$FOUND" "$BACKUP/rollback/$FILE"
    fi

    RP="$(dpkg-deb -f "$BACKUP/rollback/$FILE" Package)"
    RV="$(dpkg-deb -f "$BACKUP/rollback/$FILE" Version)"
    RA="$(dpkg-deb -f "$BACKUP/rollback/$FILE" Architecture)"

    [ "$RP" = "$P" ] || die "rollback package name mismatch: $FILE"
    [ "$RV" = "$OLDVER" ] || die "rollback version mismatch: $FILE"
    [ "$RA" = "$A" ] || die "rollback architecture mismatch: $FILE"

    ROLLBACK_DEBS+=("$BACKUP/rollback/$FILE")
    echo "OK $FILE"
done

# ----- fix old broken alternatives -----------------------------------------

section "PHP ALTERNATIVES"

for SPEC in 'php:/usr/bin/php5' 'php-config:/usr/bin/php-config5' 'phpize:/usr/bin/phpize5'
do
    NAME="${SPEC%%:*}"
    TARGET="${SPEC#*:}"
    LINK="/usr/bin/$NAME"

    [ -e "$TARGET" ] || continue

    if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
        echo "Standalone stale $LINK detected; preserving it."
        mv "$LINK" "$LINK.before-php2shell-$STAMP"

        if update-alternatives --query "$NAME" >/dev/null 2>&1; then
            update-alternatives --set "$NAME" "$TARGET" || true
        else
            update-alternatives --install "$LINK" "$NAME" "$TARGET" 50
        fi
    fi
done

if command -v php >/dev/null 2>&1; then
    echo
    php -v | head -1
fi

# ----- APT build tools ------------------------------------------------------

section "APT BUILD ENVIRONMENT"

apt_update 2>&1 | tee "$BACKUP/logs/apt-update.log" \
    || die "APT update failed"

BASIC=(build-essential dpkg-dev debhelper quilt fakeroot python)

apt_simulate "${BASIC[@]}" > "$BACKUP/logs/apt-basic-simulate.log" 2>&1 \
    || {
        cat "$BACKUP/logs/apt-basic-simulate.log"
        die "cannot resolve basic build tools"
    }

if grep -q '^Remv ' "$BACKUP/logs/apt-basic-simulate.log"; then
    cat "$BACKUP/logs/apt-basic-simulate.log"
    die "APT wants to remove packages"
fi

apt_install "${BASIC[@]}" 2>&1 | tee "$BACKUP/logs/apt-basic-install.log" \
    || die "basic build tool installation failed"

command -v dpkg-source >/dev/null 2>&1 || die "dpkg-source missing"
command -v dpkg-buildpackage >/dev/null 2>&1 || die "dpkg-buildpackage missing"
command -v quilt >/dev/null 2>&1 || die "quilt missing"

# ----- exact Dotdeb source --------------------------------------------------

section "DOWNLOAD EXACT DOTDEB SOURCE"

cd "$SRCROOT" || die "cannot enter $SRCROOT"

fetch "$DOTDEB_POOL/$DSCNAME" "$SRCROOT/$DSCNAME" \
    || die "could not download $DSCNAME"

grep -q '^Source: php5$' "$SRCROOT/$DSCNAME" || die "unexpected .dsc source"
grep -Fq "Version: $OLDVER" "$SRCROOT/$DSCNAME" || die "unexpected .dsc version"

awk '
    /^Files:/ { f=1; next }
    f && /^[ \t]/ { print $1 "  " $3; next }
    f { exit }
' "$SRCROOT/$DSCNAME" > "$SRCROOT/source.md5"

[ -s "$SRCROOT/source.md5" ] || die "cannot parse source files from .dsc"

cat "$SRCROOT/source.md5"

while read MD5 FILE
do
    [ -n "$FILE" ] || continue
    fetch "$DOTDEB_POOL/$FILE" "$SRCROOT/$FILE" \
        || die "could not download source file $FILE"
done < "$SRCROOT/source.md5"

cd "$SRCROOT" || die
md5sum -c source.md5 || die "Dotdeb source checksum mismatch"

cp -a "$DSCNAME" source.md5 "$BACKUP/source/"

# ----- extract source -------------------------------------------------------

section "EXTRACT SOURCE"

dpkg-source -x "$SRCROOT/$DSCNAME" \
    2>&1 | tee "$BACKUP/logs/dpkg-source.log" \
    || die "dpkg-source failed"

SRCDIR="$(find "$SRCROOT" -maxdepth 1 -type d -name 'php5-5.4.45*' | head -1)"
[ -n "$SRCDIR" ] || die "source directory not found"

cd "$SRCDIR" || die

# ----- remove mysql-server test-only build dependency -----------------------

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

        parts = []
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
                parts.append(clause.strip())

        out.append('%s: %s\n' % (key, ', '.join(parts)))
        continue

    out.append(line)
    i += 1

open(path, 'w').writelines(out)
PY

grep -n 'mysql-server\|virtual-mysql-server' debian/control \
    && die "mysql-server build dependency still present" \
    || true

# ----- resolve build dependencies ------------------------------------------

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
while read P
do
    [ -n "$P" ] && BUILD_DEPS+=("$P")
done < "$WORK/build-deps.txt"

echo "Build dependencies:"
printf '  %s\n' "${BUILD_DEPS[@]}"

apt_simulate "${BUILD_DEPS[@]}" > "$BACKUP/logs/apt-builddeps-simulate.log" 2>&1 \
    || {
        cat "$BACKUP/logs/apt-builddeps-simulate.log"
        die "build dependency simulation failed"
    }

if grep -q '^Remv ' "$BACKUP/logs/apt-builddeps-simulate.log"; then
    cat "$BACKUP/logs/apt-builddeps-simulate.log"
    die "APT wants to remove packages while installing build dependencies"
fi

apt_install "${BUILD_DEPS[@]}" 2>&1 | tee "$BACKUP/logs/apt-builddeps-install.log" \
    || die "build dependency installation failed"

dpkg-checkbuilddeps > "$BACKUP/logs/dpkg-checkbuilddeps.log" 2>&1 \
    || {
        cat "$BACKUP/logs/dpkg-checkbuilddeps.log"
        die "build dependencies still unsatisfied"
    }

# ----- patch ---------------------------------------------------------------

section "DOWNLOAD SECURITY PATCH"

PATCH_META="$WORK/patch-commit.json"
PATCH_REF='main'

if fetch "https://api.github.com/repos/$PATCH_REPO/commits/main" "$PATCH_META"; then
    RESOLVED="$(
        sed -n 's/^[[:space:]]*"sha":[[:space:]]*"\([0-9a-f]\{40\}\)".*/\1/p' \
            "$PATCH_META" | head -1
    )"

    if echo "$RESOLVED" | grep -Eq '^[0-9a-f]{40}$'; then
        PATCH_REF="$RESOLVED"
    fi
fi

echo "Patch ref: $PATCH_REF"

PATCHFILE="$WORK/$PATCH_NAME"

fetch \
  "https://raw.githubusercontent.com/$PATCH_REPO/$PATCH_REF/patches/$PATCH_NAME" \
  "$PATCHFILE" \
  || die "could not download PHP 5.4 security patch"

grep -q 'max_multipart_body_parts' "$PATCHFILE" \
    || die "unexpected patch: multipart limit missing"
grep -q 'zend_mm_safe_error_ex' "$PATCHFILE" \
    || die "unexpected patch: safe OOM handling missing"

sha256sum "$PATCHFILE" | tee "$BACKUP/source/php2shell-patch.sha256"
echo "$PATCH_REF" > "$BACKUP/source/php2shell-patch.ref"
cp -a "$PATCHFILE" "$BACKUP/source/"

section "PATCH DRY RUN"

cd "$SRCDIR" || die

patch --dry-run -p1 < "$PATCHFILE" \
    > "$BACKUP/logs/patch-dry-run.log" 2>&1 \
    || {
        cat "$BACKUP/logs/patch-dry-run.log"
        die "security patch does not apply cleanly to this Dotdeb source"
    }

cat "$BACKUP/logs/patch-dry-run.log"

section "APPLY PATCH"

mkdir -p debian/patches
cp -a "$PATCHFILE" debian/patches/9999-php2shell-cve-2026.patch

if [ ! -f debian/patches/series ]; then
    : > debian/patches/series
fi

grep -q '^9999-php2shell-cve-2026.patch' debian/patches/series \
    || echo '9999-php2shell-cve-2026.patch -p1' >> debian/patches/series

export QUILT_PATCHES=debian/patches
quilt push -a 2>&1 | tee "$BACKUP/logs/quilt.log" \
    || die "quilt failed to apply patch"

# ----- bump package version -------------------------------------------------

section "BUMP PACKAGE VERSION"

{
    echo "php5 ($NEWVER) wheezy; urgency=high"
    echo
    echo "  * Local security rebuild for CVE-2026-109618 and CVE-2026-109619."
    echo
    echo " -- Local Security Build <root@localhost>  $(date -R)"
    echo
    cat debian/changelog
} > "$WORK/changelog.new"

mv "$WORK/changelog.new" debian/changelog

[ "$(dpkg-parsechangelog -SVersion)" = "$NEWVER" ] \
    || die "failed to set package version"

# ----- build ---------------------------------------------------------------

section "BUILD"

export DEB_BUILD_OPTIONS='nocheck parallel=2'

dpkg-buildpackage -b -uc -us 2>&1 | tee "$BACKUP/logs/php54-build.log"
BUILD_RC=${PIPESTATUS[0]}

[ "$BUILD_RC" = "0" ] || die "PHP build failed"

# ----- locate newly built packages -----------------------------------------

section "VERIFY BUILT PACKAGES"

NEW_DEBS=()

for P in "${INSTALLED_CORE[@]}"
do
    A="$(dpkg-query -W -f='${Architecture}' "$P")"
    F="$(find "$SRCROOT" -maxdepth 1 -type f \
        -name "${P}_${NEWVER}_${A}.deb" | head -1)"

    [ -n "$F" ] || die "new package was not built: $P ($A)"

    NP="$(dpkg-deb -f "$F" Package)"
    NV="$(dpkg-deb -f "$F" Version)"
    NA="$(dpkg-deb -f "$F" Architecture)"

    [ "$NP" = "$P" ] || die "wrong package name in $F"
    [ "$NV" = "$NEWVER" ] || die "wrong package version in $F"
    [ "$NA" = "$A" ] || die "wrong package architecture in $F"

    NEW_DEBS+=("$F")
    cp -a "$F" "$PKGOUT/"
    echo "OK $(basename "$F")"
done

cp -a "$PATCHFILE" "$PKGOUT/"
cp -a "$BACKUP/source/php2shell-patch.sha256" "$PKGOUT/"
cp -a "$BACKUP/source/php2shell-patch.ref" "$PKGOUT/"

# ----- offline test ---------------------------------------------------------

section "OFFLINE TEST"

rm -rf "$STAGE"
mkdir -p "$STAGE"

for F in "${NEW_DEBS[@]}"
do
    dpkg-deb -x "$F" "$STAGE" || die "cannot stage $F"
done

NEWPHP="$STAGE/usr/bin/php5"
[ -x "$NEWPHP" ] || die "staged /usr/bin/php5 missing"

"$NEWPHP" -n -v || die "new PHP binary cannot start"
"$NEWPHP" -n -i > "$BACKUP/diagnostics/new-php-info.txt"

grep -q '^PHP API => 20100412$' "$BACKUP/diagnostics/new-php-info.txt" \
    || die "PHP API changed"
grep -q '^PHP Extension => 20100525$' "$BACKUP/diagnostics/new-php-info.txt" \
    || die "PHP extension ABI changed"
grep -q '^Zend Extension => 220100525$' "$BACKUP/diagnostics/new-php-info.txt" \
    || die "Zend ABI changed"
grep -q '^PHP Extension Build => API20100525,NTS$' "$BACKUP/diagnostics/new-php-info.txt" \
    || die "new PHP is not the expected NTS build"

ldd "$NEWPHP" > "$BACKUP/diagnostics/new-php-ldd.txt"
grep -q 'not found' "$BACKUP/diagnostics/new-php-ldd.txt" \
    && die "new PHP has unresolved libraries"

if [ "$HAS_APACHE" = "1" ]; then
    NEWLIB="$STAGE/usr/lib/apache2/modules/libphp5.so"
    [ -f "$NEWLIB" ] || die "staged libphp5.so missing"
    ldd "$NEWLIB" > "$BACKUP/diagnostics/new-libphp5-ldd.txt"
    grep -q 'not found' "$BACKUP/diagnostics/new-libphp5-ldd.txt" \
        && die "new libphp5.so has unresolved libraries"
fi

# Test all currently configured extensions against the new ABI.
"$NEWPHP" \
    -c /etc/php5/cli/php.ini \
    -d display_errors=1 \
    -d display_startup_errors=1 \
    -m \
    > "$BACKUP/diagnostics/new-php-modules.txt" \
    2> "$BACKUP/diagnostics/new-php-startup-errors.txt"

if grep -Ei \
'PHP Startup|Unable to load|undefined symbol|cannot open shared object|segmentation|segfault' \
"$BACKUP/diagnostics/new-php-startup-errors.txt"
then
    cat "$BACKUP/diagnostics/new-php-startup-errors.txt"
    die "current extension set is not compatible with rebuilt PHP"
fi

"$NEWPHP" -n -r '
$v = ini_get("max_multipart_body_parts");
if ($v === false) {
    fwrite(STDERR, "max_multipart_body_parts missing\n");
    exit(1);
}
echo "max_multipart_body_parts=", $v, "\n";
' || die "security-patch signal is missing"

# ----- service restart blocker ---------------------------------------------

save_policy()
{
    [ "$POLICY_SAVED" = "0" ] || return 0
    POLICY_SAVED=1

    if [ -e /usr/sbin/policy-rc.d ]; then
        HAD_POLICY=1
        cp -a /usr/sbin/policy-rc.d "$BACKUP/policy-rc.d.original"
    fi
}

block_services()
{
    save_policy
    cat > /usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF
    chmod 755 /usr/sbin/policy-rc.d
}

restore_policy()
{
    [ "$POLICY_SAVED" = "1" ] || return 0

    if [ "$HAD_POLICY" = "1" ]; then
        cp -a "$BACKUP/policy-rc.d.original" /usr/sbin/policy-rc.d
    else
        rm -f /usr/sbin/policy-rc.d
    fi
}

# ----- rollback -------------------------------------------------------------

rollback()
{
    echo
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo " INSTALL FAILED -- ROLLING BACK"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo

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
        cp -a "$BACKUP/runtime/usr/lib/apache2/modules/libphp5.so" \
            /usr/lib/apache2/modules/libphp5.so
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
    echo "PHP after rollback:"
    /usr/bin/php5 -v || true

    echo
    echo "Backup:"
    echo "$BACKUP"

    exit 1
}

signal_handler()
{
    echo
    echo "Signal received."

    if [ "$INSTALL_STARTED" = "1" ]; then
        rollback
    fi

    restore_policy
    exit 130
}

trap signal_handler INT TERM

# ----- install --------------------------------------------------------------

section "INSTALL PATCHED PACKAGES"

if [ "$HAS_APACHE" = "1" ]; then
    apache2ctl configtest || die "Apache configuration is invalid before install"
fi

block_services
INSTALL_STARTED=1

dpkg -i "${NEW_DEBS[@]}" || rollback

section "VERIFY INSTALLED PACKAGES"

for P in "${INSTALLED_CORE[@]}"
do
    V="$(dpkg-query -W -f='${Version}' "$P" 2>/dev/null || true)"
    echo "$P    $V"
    [ "$V" = "$NEWVER" ] || rollback
done

/usr/bin/php5 -v || rollback
/usr/bin/php5 -v 2>&1 | head -1 | grep -Fq "$NEWVER" || rollback

/usr/bin/php5 -m \
    > "$BACKUP/diagnostics/php-modules-after.txt" \
    2> "$BACKUP/diagnostics/php-startup-after.txt" \
    || rollback

if grep -Ei \
'PHP Startup|Unable to load|undefined symbol|cannot open shared object|segmentation|segfault' \
"$BACKUP/diagnostics/php-startup-after.txt"
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

    apache2ctl -M > "$BACKUP/diagnostics/apache-modules-after.txt" 2>&1 \
        || rollback

    grep -q 'mpm_prefork_module' "$BACKUP/diagnostics/apache-modules-after.txt" \
        || rollback
    grep -q 'php5_module' "$BACKUP/diagnostics/apache-modules-after.txt" \
        || rollback

    grep -E 'php|mpm' "$BACKUP/diagnostics/apache-modules-after.txt"
fi

# ----- final state ----------------------------------------------------------

INSTALL_STARTED=0

section "FINAL STATE"

/usr/bin/php5 -v

echo
/usr/bin/php5 -r '
echo "max_multipart_body_parts=",
     ini_get("max_multipart_body_parts"),
     "\n";
'

echo
echo "Installed patched packages:"
for P in "${INSTALLED_CORE[@]}"
do
    dpkg-query -W -f='${binary:Package}\t${Version}\t${Status}\n' "$P"
done

if [ -f /usr/lib/apache2/modules/libphp5.so ]; then
    echo
    echo "libphp5.so:"
    sha256sum /usr/lib/apache2/modules/libphp5.so
fi

# ----- archive --------------------------------------------------------------

section "ARCHIVE BACKUP"

tar czpf "$BACKUP.tar.gz" -C /backup "$(basename "$BACKUP")" \
    || echo "WARNING: could not create compressed backup archive"

if [ -f "$BACKUP.tar.gz" ]; then
    sha256sum "$BACKUP.tar.gz" > "$BACKUP.tar.gz.sha256"
    ls -lh "$BACKUP.tar.gz"
    cat "$BACKUP.tar.gz.sha256"
fi

section "PHP 5.4 PHP2SHELL UPDATE SUCCESSFUL"

echo
echo "Installed:"
/usr/bin/php5 -v | head -1

echo
echo "Built packages:"
echo "  $PKGOUT"

echo
echo "Backup:"
echo "  $BACKUP"
echo "  $BACKUP.tar.gz"

echo
echo "Build tree:"
echo "  $WORK"

echo
echo "DO NOT DELETE THE BACKUP."
echo

exit 0
