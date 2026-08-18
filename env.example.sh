#!/bin/bash
# Copy to env.local.sh and fill in. env.local.sh is gitignored; this file is not,
# so nothing here may name a real machine, account, or address.
#
#   cp env.example.sh env.local.sh && $EDITOR env.local.sh

# The machine that compiles. Runs the old system and the old Xcode, which is the
# only combination that produces a binary the target will load.
BT_BUILD_HOST="user@build.example.lan"
BT_BUILD_DIR="Projects/btunes"          # path on BUILD, relative to its home

# The machine that plays music. Its library is read-only, always.
BT_TARGET_HOST="user@target.example.lan"
BT_TARGET_DIR="Projects/btunes"         # path on TARGET, relative to its home

# Set to 1 while BUILD has other long work on it, such as an audio conversion
# run. Every remote step of a deploy then takes the processor and the disk only
# when nothing else wants them. Builds get slower; nothing else changes.
# deploy.sh --gentle and --full-speed override this per run.
BT_BUILD_GENTLE=0
