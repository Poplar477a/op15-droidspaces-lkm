#!/system/bin/sh
if ! command -v ui_print >/dev/null 2>&1; then
	ui_print() { echo "$1"; }
fi
ui_print "- phDroid OP15 (auto-load build)"
ui_print "- target: android16-6.12 / KMI gen 6 (6.12.x-android16-6)"
chmod 0755 "$MODPATH"/*.sh 2>/dev/null
chmod 0755 "$MODPATH"/tools/*.sh 2>/dev/null
ui_print "- installed to: $MODPATH"
ui_print "- auto-load ON (no no_boot); bootloop guard still active."
ui_print "- load right now: sh $MODPATH/load.sh"
