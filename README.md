# sab (Spinners And Bars)

A simple program for printing spinners and bars to stdout.

```
Usage: sab [OPTION]...
sab will draw bars/spinners based on the values piped in through
stdin.

To draw a simple bar, simply pipe a value between 0-100 into sab:
echo 35 | sab
====      

You can customize your bar with the '--steps' option:
echo 35 | sab -s ' -='
===-      

To draw a simple spinner, simply set the length of the bar to 1
and set max to be the last step:
echo 2 | sab -l 1 -M 3 -s '/-\|'
\

sab will draw multible lines, one for each line piped into it.
echo -e '0\n1\n2\n3' | sab -l 1 -M 3 -s '/-\|'
/
-
\
|

Options:
	-h, --help        	print this message to stdout
	-l, --length=VALUE	the length of the bar (default: 10)
	-m, --min=VALUE   	mininum value (default: 0)
	-M, --max=VALUE   	maximum value (default: 100)
	-s, --steps=VALUE 	list of steps (default: ' =')

```
