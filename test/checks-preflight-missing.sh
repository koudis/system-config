# Runs only under expect-fail on the bare privileged image. test/run.sh asserts
# the non-zero exit and the message; these assert the image is genuinely missing
# the prerequisites, so the negative test cannot pass for the wrong reason.
assert_cmd "gcc absent"      bash -c '! command -v gcc'
assert_cmd "ninja absent"    bash -c '! command -v ninja'
assert_cmd "msgfmt absent"   bash -c '! command -v msgfmt'
assert_cmd "flatpak absent"  bash -c '! command -v flatpak'
assert_cmd "git present"     command -v git
assert_cmd "curl present"    command -v curl
