# we do not need this
MK_host_egacy= no

.sinclude <src.opts.mk>

PACKAGE?= bmake

.if defined(.PARSEDIR)
# make sure this is available to unit-tests/Makefile
.export SRCTOP
.endif

.if exists(${.CURDIR}/tests)
PROG= make
.if ${PROGNAME:U} != "bmake"
LINKS= ${BINDIR}/make ${BINDIR}/bmake
MLINKS= ${MAN} b${MAN}
.endif
.endif

# hack to not add tests to tests subdir since this is included from
# there and to avoid renaming things that require changes to generated
# files.
.if defined(MK_TESTS) && ${MK_TESTS} != no && exists(${.CURDIR}/tests)
SUBDIR+= tests
.endif

WARNS?=3
CFLAGS+= -DNO_PWD_OVERRIDE

.if make(after-import)
# use our preferred value
DEFAULT_SYS_PATH= .../share/mk:/usr/share/mk
.export DEFAULT_SYS_PATH
.endif

.if ${MACHINE} != "host"
FILEMON_H ?= ${SRCTOP}/sys/dev/filemon/filemon.h
.endif
