#
# SPDX-License-Idendifier: BSD-2-Clause
#
# Copyright (c) 2025 FreeBSD Foundation
#
# This sofware was developed by Cy Schubert <cy@FreeBSD.org>
# under sponsorship from the FreeBSD Foundation.
#

PROG=	kinit

LIBADD=	kadm5srv_mit kdb5 gssrpc gssapi_krb5 krb5 k5crypto com_err \
	krb5profile krb5support sys

SRCS=	kinit.c \
	kinit_kdb.c

CFLAGS+=-I${KRB5_DIR}/include \
	-I${KRB5_SRCTOP}/include

MAN=	kinit.1

kinit.1:	kinit.man

CLEANFILES+=	kinit.1

.include <bsd.prog.mk>

.SUFFIXES: .h .c. .man .1

.man.1:
	@cp ${.ALLSRC} ${.TARGET}

.PATH:	${KRB5_DIR}/clients/kinit \
	${KRB5_DIR}/man
