#!/bin/bash

BASE="project"

[[ -d "${BASE}" ]] && rm -rf "${BASE}"

mkdir -p "${BASE}/versions/v1" \
         "${BASE}/versions/v2" \
         "${BASE}/versions/v3"

echo "# README версия 1" > "${BASE}/versions/v1/README.md"
echo "# README версия 2" > "${BASE}/versions/v2/README.md"
echo "# README версия 3" > "${BASE}/versions/v3/README.md"

find "${BASE}/versions" -type f

( cd "${BASE}" && ln -s "versions/v1" current_version )

ls -la "${BASE}/current_version"
ls "${BASE}/current_version/"

HARDLINKS_DIR="${BASE}/hardlinks_v1"
mkdir -p "${HARDLINKS_DIR}"
cp -l "${BASE}/current_version/"* "${HARDLINKS_DIR}/"
ls -lai "${HARDLINKS_DIR}/"

echo -n "  Оригинал      : "; stat --format="%i  %n" "${BASE}/versions/v1/README.md"
echo -n "  Жёсткая ссылка: "; stat --format="%i  %n" "${HARDLINKS_DIR}/README.md"


echo -n "  До смены      : "; readlink "${BASE}/current_version"
echo -n "  Содержимое    : "; cat "${BASE}/current_version/README.md"


( cd "${BASE}" && ln -sfT "versions/v2" current_version )


echo -n "  После смены   : "; readlink "${BASE}/current_version"
echo -n "  Содержимое    : "; cat "${BASE}/current_version/README.md"


echo -n "  current_version/README.md : "; cat "${BASE}/current_version/README.md"
echo -n "  hardlinks_v1/README.md    : "; cat "${HARDLINKS_DIR}/README.md"
