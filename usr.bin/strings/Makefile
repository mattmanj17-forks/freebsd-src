.include <src.opts.mk>

PACKAGE=	toolchain

ELFTCDIR=	${SRCTOP}/contrib/elftoolchain

.PATH: ${ELFTCDIR}/strings

PROG=	strings

LIBADD=	elftc elf

.if ${MK_CASPER} != "no" && !defined(BOOTSTRAPPING) && !defined(NXB_TARGET)
LIBADD+=	casper
LIBADD+=	cap_fileargs
CFLAGS+=	-DWITH_CASPER
.endif

CFLAGS+=-I${ELFTCDIR}/libelftc -I${ELFTCDIR}/common

.include <bsd.prog.mk>
