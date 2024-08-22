#!/bin/bash
set -e

declare CHANGED_FILES=$(git diff --name-only --cached --relative '*.jsx' '*.js' | xargs -r ls -1 2>/dev/null)

if [ -n "$CHANGED_FILES" ]; then
  npm run lint:changed -- $CHANGED_FILES
  [ $? -ne 0 ] && exit 1
fi
