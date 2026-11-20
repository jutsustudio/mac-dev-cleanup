# Records assets/demo.gif. Run demo/setup.sh first, then: vhs demo/demo.tape
# The binary must be built with -DDEMO_HOME so it reads $HOME (see demo/setup.sh).
Output assets/demo.gif
Output demo/demo.mp4

Set Shell "bash"
Set FontFamily "Menlo"
Set FontSize 15
Set Width 1640
Set Height 500
Set Padding 28
Set Framerate 24
Set TypingSpeed 45ms
Set CursorBlink false
Set Theme { "name": "PixelDisk", "background": "#08090a", "foreground": "#c9cbcd", "cursor": "#5bdb75", "selection": "#1b1d1e", "black": "#08090a", "red": "#e5484d", "green": "#5bdb75", "yellow": "#e9c941", "blue": "#4f8fe8", "magenta": "#e13ca1", "cyan": "#33d6e0", "white": "#c9cbcd", "brightBlack": "#808386", "brightRed": "#e5484d", "brightGreen": "#5bdb75", "brightYellow": "#e9c941", "brightBlue": "#4f8fe8", "brightMagenta": "#e13ca1", "brightCyan": "#33d6e0", "brightWhite": "#ffffff" }

Hide
Type "export HOME=/Volumes/MDCDemo/home PATH=/private/tmp/mdc-demo/bin:/usr/bin:/bin; cd; PS1='\[\e[32m\]>\[\e[0m\] '; clear"
Enter
Show

Sleep 600ms
Type "mac-dev-cleanup scan"
Sleep 400ms
Enter
Sleep 5s

Hide
Type "clear"
Enter
Show
Type "mac-dev-cleanup clean --yes"
Sleep 400ms
Enter
Sleep 4.5s

Hide
Type "clear"
Enter
Show
Type "mac-dev-cleanup scan"
Sleep 400ms
Enter
Sleep 4s
