# doaz

![image example of doaz](./assets/example.png)

`doaz`, a faithful port of the `doas` privilege escalation tool, written in Zig.

# About

`doaz` aims to be a drop-in replacement for `doas` with some extra features, a better
user interface, and a lot more runtime safety checks with a focus on simplicity and security.

# TODO

- allow for rules
- parsing a config file
- allow running as users other than root
- create better testing and fuzzing
- consider a "compat" mode so we can extend on features from `doas`
- figure out the license
- consider removing all dependencies on `C` (might be unrealistic)
- make things a lot easier to get correct (ie: better error messages for config parsing errors etc...)
- cross platform compilation and usage (right now there is just Linux) as well as testing
  - linux
  - bsd
  - mac
  - windows

## Zig

- built with `Zig` 0.14.0-dev.1911+3bf89f55c (mach)
  there are breaking changes from the last version to 0.14.0+
  but I will do my best to keep things up to date. Feel free
  to open a PR or issue if you have any issues or questions

## Thanks to:

- [https://github.com/dmgk/zig-getopt](dmgk/zig-getopt) OBSD License
  for the getopt implementation
- [https://github.com/rockorager/libvaxis](rockorager/libvaxis) MIT license
  for the reference on configuring the terminal state
- doas source code
