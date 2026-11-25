// SPDX-License-Identifier: GPL-2.0
#define _GNU_SOURCE
#include <signal.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t received;

static void handler(int sig)
{
	received = sig;
}

static long long ns(struct timespec t)
{
	return (long long)t.tv_sec * 1000000000 + t.tv_nsec;
}

int main(void)
{
	struct timespec before, libc_time, after;
	long long previous = 0;

	if (signal(SIGUSR1, handler) == SIG_ERR || raise(SIGUSR1) ||
	    received != SIGUSR1) {
		puts("FAIL signal");
		return 1;
	}
	for (int i = 0; i < 100; i++) {
		if (syscall(SYS_clock_gettime, CLOCK_MONOTONIC, &before) ||
		    clock_gettime(CLOCK_MONOTONIC, &libc_time) ||
		    syscall(SYS_clock_gettime, CLOCK_MONOTONIC, &after) ||
		    ns(before) < previous || ns(libc_time) < ns(before) ||
		    ns(after) < ns(libc_time)) {
			puts("FAIL clock_gettime");
			return 1;
		}
		previous = ns(after);
	}
	return 0;
}
