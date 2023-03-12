#!/bin/sh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.


SYMBOL_FILE_BASE="${BUILD_DIR}/${BUILD_STYLE}/${EXECUTABLE_NAME}"

# Generate breakpad symbols only for release builds.
if [ "${CONFIGURATION}" != "Deployment" ]; then
  exit 0;
fi

for arch in ${ARCHS}; do
  SYMBOL_FILE="${SYMBOL_FILE_BASE}-${arch}.breakpadsymbols"
  SYMBOL_SOURCE="${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}"
  if [ "${SYMBOL_SOURCE}" -nt "${SYMBOL_FILE}" ]; then
    "${SRCROOT}/google-breakpad/src/tools/mac/dump_syms/build/Release/dump_syms" -a ${arch} "${SYMBOL_SOURCE}" > "${SYMBOL_FILE}"
  fi
done
