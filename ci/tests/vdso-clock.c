// SPDX-License-Identifier: GPL-2.0
#define _GNU_SOURCE
#include <errno.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/auxv.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>
#include "parse_vdso.h"

int main(int argc, char **argv)
{
	/* A distinctive error makes a fallback syscall visible to the caller. */
	struct sock_filter insns[] = {
		BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
		BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_clock_gettime, 0, 1),
		BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EDOM),
		BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
	};
	struct sock_fprog filter = { sizeof(insns) / sizeof(insns[0]), insns };
	int (*read_clock)(clockid_t, struct timespec *);
	unsigned long base = getauxval(AT_SYSINFO_EHDR);
	struct timespec ts;
	int ret;

	if (!base)
		return 1;
	vdso_init_from_sysinfo_ehdr(base);
	read_clock = vdso_sym("LINUX_2.6", "__vdso_clock_gettime");
	if (!read_clock || read_clock(CLOCK_MONOTONIC, &ts))
		return 1;
	if (prctl(PR_SET_NO_NEW_PRIVS, 1L, 0L, 0L, 0L) ||
	    prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &filter))
		return 1;
	if (syscall(SYS_clock_gettime, CLOCK_MONOTONIC, &ts) != -1 || errno != EDOM)
		return 1;
	ret = read_clock(CLOCK_MONOTONIC, &ts);
	if (ret == -EDOM) {
		puts("vDSO clock_gettime: syscall fallback");
		return 0;
	}
	if (ret)
		return 1;
	puts("vDSO clock_gettime: userspace fast path");
	return argc > 1 && !strcmp(argv[1], "time-travel");
}
