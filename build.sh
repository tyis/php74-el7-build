#!/bin/bash
# Build PHP 7.4.33-33 (Remi SRPM) RPMs for CentOS 7 (EL7).
#
# Usage (inside a CentOS 7 environment, e.g. a centos:7 container):
#   ./build.sh
# Output: RPMs are written to ~/rpmbuild/RPMS/x86_64/
#
# Notes:
# - CentOS 7 is EOL: base repos are pointed at vault.centos.org (7.9.2009)
#   and EPEL at the Fedora archive.
# - The Remi SRPM uses Rich Dependencies, which el7 rpm cannot parse,
#   so it is extracted with rpm2cpio instead of `rpm -i`.
# - php-7.4.33-33.spec requires libpq-devel (changed from postgresql-devel
#   in -31). No EL7 repository ships a package of that name; the PGDG
#   repository ships it as libpq5-devel, so the spec is adjusted below.
# - The spec's ICU requirement is versioned (>= 78 in -33, >= 74 in -31)
#   while EL7 ships ICU 50, so the version constraint is removed with a
#   version-agnostic pattern that works for every 7.4.33 revision.
set -e
cd "$(dirname "$0")"

SRPM=php-7.4.33-33.remi.src.rpm

# --- 1. Repositories -------------------------------------------------------
rm -f /etc/yum.repos.d/CentOS-Sources.repo /etc/yum.repos.d/CentOS-CR.repo \
      /etc/yum.repos.d/CentOS-Media.repo /etc/yum.repos.d/CentOS-fasttrack.repo \
      /etc/yum.repos.d/CentOS-Debuginfo.repo /etc/yum.repos.d/CentOS-x86_64-kernel.repo
sed -i -e 's|^mirrorlist=|#mirrorlist=|g' \
       -e 's|^#baseurl=http://mirror.centos.org/centos/$releasever|baseurl=https://vault.centos.org/7.9.2009|g' \
       /etc/yum.repos.d/CentOS-Base.repo
yum clean all

# EPEL (archive) and Remi release packages
yum -y install https://archives.fedoraproject.org/pub/archive/epel/7/x86_64/Packages/e/epel-release-7-14.noarch.rpm \
               https://rpms.remirepo.net/enterprise/remi-release-7.rpm || \
  rpm -q epel-release remi-release >/dev/null
# Point EPEL at the archive (metalink disabled) and remi-safe at its baseurl
python - << 'PYEOF'
import re
p = '/etc/yum.repos.d/epel.repo'
s = open(p).read()
s = re.sub(r'^metalink=', '#metalink=', s, flags=re.M)
s = s.replace('#baseurl=http://download.example/pub/epel/7/$basearch',
              'baseurl=https://archives.fedoraproject.org/pub/archive/epel/7/$basearch')
s = s.replace('#baseurl=http://download.example/pub/epel/7/$basearch/debug',
              'baseurl=https://archives.fedoraproject.org/pub/archive/epel/7/$basearch/debug')
s = s.replace('#baseurl=http://download.example/pub/epel/7/source/tree/',
              'baseurl=https://archives.fedoraproject.org/pub/archive/epel/7/SRPMS')
open(p, 'w').write(s)
p = '/etc/yum.repos.d/remi-safe.repo'
s = open(p).read()
s = re.sub(r'^mirrorlist=.*$', '', s, flags=re.M)
s = s.replace('#baseurl=http://rpms.remirepo.net/enterprise/7/safe/$basearch/',
              'baseurl=https://rpms.remirepo.net/enterprise/7/safe/$basearch/')
open(p, 'w').write(s)
PYEOF

# PGDG repository (provides libpq-devel required by the -33 spec)
cat > /etc/yum.repos.d/pgdg.repo << 'EOF'
[pgdg15]
name=PostgreSQL 15 for RHEL 7
baseurl=https://download.postgresql.org/pub/repos/yum/15/redhat/rhel-7-x86_64/
enabled=1
gpgcheck=0
[pgdg-common]
name=PostgreSQL common for RHEL 7
baseurl=https://download.postgresql.org/pub/repos/yum/common/redhat/rhel-7-x86_64/
enabled=1
gpgcheck=0
EOF

yum -y install rpm-build yum-utils cpio gcc gcc-c++ make

# --- 2. Extract the SRPM ---------------------------------------------------
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS} ~/work
cd ~/work
[ -f "$SRPM" ] || curl -LO "https://rpms.remirepo.net/SRPMS/$SRPM"
rpm2cpio "$SRPM" | cpio -idm --quiet
cp php74.spec ~/rpmbuild/SPECS/
for f in *; do
  case "$f" in *.src.rpm|php74.spec) ;; *) mv "$f" ~/rpmbuild/SOURCES/ ;; esac
done

# --- 3. Adjust the spec for EL7 --------------------------------------------
cd ~/rpmbuild/SPECS
# Use the system libgd instead of the bundled one
sed -i 's|^%global with_libgd   1|%global with_libgd   0|' php74.spec
# EL7 provides oniguruma-devel (EPEL), not oniguruma5php-devel
sed -i 's|^BuildRequires: oniguruma5php-devel|BuildRequires: oniguruma-devel|' php74.spec
# -33 requires libpq-devel; on EL7 the PGDG package is named libpq5-devel
sed -i 's|^BuildRequires: libpq-devel|BuildRequires: libpq5-devel|' php74.spec
# Drop the ICU version constraint (EL7 ships ICU 50); version-agnostic so it
# works for -31 (>= 74), -32 and -33 (>= 78) alike
sed -i -E 's|(pkgconfig\(icu-[a-z0-9-]+\))[[:space:]]*>=[[:space:]]*[0-9.]+|\1|' php74.spec

# --- 4. Build ---------------------------------------------------------------
yum-builddep -y php74.spec
rpmbuild -ba php74.spec

echo "Done. RPMs: $(ls ~/rpmbuild/RPMS/x86_64/*.rpm | wc -l) packages in ~/rpmbuild/RPMS/x86_64/"
