# sab (Spinners And Bars)

A simple program for printing spinners and bars to stdout.

```
Usage: sab [OPTION]... [CURR]...
Given a min, max and current value, sab will draw bars/spinners
to stdout. The format of the bar/spinner is read from stdin and
is a line seperated lists of steps.

To draw a simple bar, simply pipe your empty and full chars into
sab, and give it the current value:
echo -e '.\n=' | sab 35
====......

For a more fine grained bar, simply pipe in more steps:
echo -e '.\n-\n=' | sab 35
===-......

To draw a simple spinner, simply set the length of the bar to 1
and set min to 0 and max to be the last step:
echo -e '/\n-\n\\\n|' | sab -l 1 -M 3 3
|

sab will draw multible lines if provided with multible current
values.
echo -e '/\n-\n\\\n|' | sab -l 1 -M 3 0 1 2 3
/
-
\
|

Options:
	-h, --help        	print this message to stdout
	-l, --length=VALUE	the length of the bar (default: 10)
	-m, --min=VALUE   	mininum value (default: 0)
	-M, --max=VALUE   	maximum value (default: 100)

```
