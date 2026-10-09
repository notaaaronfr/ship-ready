# Records docs/demo.gif with VHS (https://github.com/charmbracelet/vhs).
# Every line shown is real output from the ship-ready scripts on the eval fixture.
#
# Usage: vhs docs/demo.tape   (run from the repository root; needs the Python
#        tools ruff, mypy, bandit, pytest, pytest-cov installed)

Output docs/demo.gif

Set Shell "bash"
Set Theme "Catppuccin Mocha"
Set FontSize 15
Set Width 1600
Set Height 660
Set Padding 24
Set TypingSpeed 35ms

Hide
Type "export REPO=$PWD S=$PWD/skills/ship-ready/scripts && cd $(mktemp -d) && cp -R $REPO/evals/fixtures/order-service . && export PS1='\[\e[1;35m\]❯\[\e[0m\] ' && clear"
Enter
Sleep 500ms
Show

Type "# An AI agent wants to add a dependency. Does it even exist?"
Sleep 400ms
Enter
Type "$S/verify_package.sh pypi py-money-decimal-utils"
Sleep 300ms
Enter
Wait+Screen@20s /MISSING|OK|ERROR/
Sleep 2.5s

Type "# Is this AI-written service ready to ship?"
Sleep 400ms
Enter
Type "$S/quality_gate.sh order-service 2>/dev/null | sed -n '/SUMMARY/,$p'"
Sleep 300ms
Enter
Wait+Screen@90s /VERDICT: [A-Z_]+/
Sleep 7s
