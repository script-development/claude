#!/usr/bin/env bash
#
# Run every shell test suite shipped under plugins/.
#
# Suites are DISCOVERED by the `*.test.sh` marker, never listed, so a new suite is picked up
# without touching CI. Every suite in the tree resolves its subject from its own BASH_SOURCE, so
# none needs a particular working directory or any arguments; each runs as plain `bash <path>`,
# the way its own header says to run it.
#
# Every suite runs even after one fails, so a single red run reports all the failures at once.
# An empty discovery is a failure, not a pass: zero suites would otherwise go green having
# checked nothing.
#
# Usage (from the repository root):
#
#   bash .github/scripts/run-plugin-suites.sh
#
# Deliberately bash 3.2-compatible (no mapfile, no associative arrays): the macOS job runs it,
# and the suites, under the stock /bin/bash.

set -u

root=${1:-plugins}

suites=$(find "$root" -name '*.test.sh' -type f | LC_ALL=C sort)
if [ -z "$suites" ]; then
    echo "::error::no *.test.sh suites found under $root/"
    exit 1
fi

echo "bash: $(bash -c 'echo "$BASH_VERSION"') ($(command -v bash))"

total=0
failed=""
while IFS= read -r suite; do
    [ -n "$suite" ] || continue
    total=$((total + 1))
    echo "::group::$suite"
    # stdin from /dev/null: the suite must not eat the rest of this loop's input.
    if bash "$suite" < /dev/null; then
        status=pass
    else
        status=fail
    fi
    echo "::endgroup::"
    if [ "$status" = pass ]; then
        echo "PASS  $suite"
    else
        echo "::error file=$suite::suite exited nonzero"
        echo "FAIL  $suite"
        failed="$failed $suite"
    fi
done <<EOF
$suites
EOF

echo
if [ -n "$failed" ]; then
    n=$(echo "$failed" | wc -w | tr -d ' ')
    echo "FAILED: $n of $total suites:$failed"
    exit 1
fi
echo "OK: all $total suites passed"
