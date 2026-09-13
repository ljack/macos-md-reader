#!/bin/zsh
# Reduces xcodebuild output to diagnostics + result. Exit status comes from xcodebuild via pipefail in the Makefile.
grep -E --line-buffered "error:|warning: .*MDReader/|Test Case .*(failed|passed)|Test Suite .*(failed|passed)|Executed .* tests|\*\* (BUILD|TEST) " | grep -vE "appintentsmetadataprocessor"
exit 0
