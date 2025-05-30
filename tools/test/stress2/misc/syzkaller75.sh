#!/bin/sh

# panic: vm_pager_assert_in: page 0xfffffe001987bcc0 is mapped
# cpuid = 10
# time = 1745335200
# KDB: stack backtrace:
# db_trace_self_wrapper() at db_trace_self_wrapper+0x2b/frame 0xfffffe0108807700
# vpanic() at vpanic+0x136/frame 0xfffffe0108807830
# panic() at panic+0x43/frame 0xfffffe0108807890
# vm_pager_assert_in() at vm_pager_assert_in+0x1fa/frame 0xfffffe01088078d0
# vm_pager_get_pages() at vm_pager_get_pages+0x3d/frame 0xfffffe0108807920
# vm_fault_getpages() at vm_fault_getpages+0x22b/frame 0xfffffe0108807980
# vm_fault_object() at vm_fault_object+0x2ab/frame 0xfffffe01088079e0
# vm_fault() at vm_fault+0x2d1/frame 0xfffffe0108807b40
# vm_map_wire_locked() at vm_map_wire_locked+0x385/frame 0xfffffe0108807bf0
# vm_mmap_object() at vm_mmap_object+0x2fd/frame 0xfffffe0108807c50
# vn_mmap() at vn_mmap+0x152/frame 0xfffffe0108807ce0
# kern_mmap() at kern_mmap+0x621/frame 0xfffffe0108807dc0
# sys_mmap() at sys_mmap+0x42/frame 0xfffffe0108807e00
# amd64_syscall() at amd64_syscall+0x15a/frame 0xfffffe0108807f30
# fast_syscall_common() at fast_syscall_common+0xf8/frame 0xfffffe0108807f30
# --- syscall (0, FreeBSD ELF64, syscall), rip = 0x82438d7fa, rsp = 0x824847f68, rbp = 0x824847f90 ---
# KDB: enter: panic
# [ thread pid 43067 tid 146060 ]
# Stopped at      kdb_enter+0x33: movq    $0,0x124d7e2(%rip)
# db> x/s version
# version: FreeBSD 15.0-CURRENT #2 main-n276647-a098111a28ed-dirty: Tue Apr 22 16:37:39 CEST 2025
# pho@mercat1.netperf.freebsd.org:/usr/src/sys/amd64/compile/PHO
# db> 

[ `id -u ` -ne 0 ] && echo "Must be root!" && exit 1

. ../default.cfg
set -u
prog=$(basename "$0" .sh)
cat > /tmp/$prog.c <<EOF
// https://syzkaller.appspot.com/bug?id=bab5b2c0d3e8f95d52a06ab501ddb3c11200a5c9
// autogenerated by syzkaller (https://github.com/google/syzkaller)
// syzbot+1cc9ede76727d2ea2e8d@syzkaller.appspotmail.com

#define _GNU_SOURCE

#include <sys/types.h>

#include <errno.h>
#include <pthread.h>
#include <pwd.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/endian.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static void kill_and_wait(int pid, int* status)
{
  kill(pid, SIGKILL);
  while (waitpid(-1, status, 0) != pid) {
  }
}

static void sleep_ms(uint64_t ms)
{
  usleep(ms * 1000);
}

static uint64_t current_time_ms(void)
{
  struct timespec ts;
  if (clock_gettime(CLOCK_MONOTONIC, &ts))
    exit(1);
  return (uint64_t)ts.tv_sec * 1000 + (uint64_t)ts.tv_nsec / 1000000;
}

static void thread_start(void* (*fn)(void*), void* arg)
{
  pthread_t th;
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setstacksize(&attr, 128 << 10);
  int i = 0;
  for (; i < 100; i++) {
    if (pthread_create(&th, &attr, fn, arg) == 0) {
      pthread_attr_destroy(&attr);
      return;
    }
    if (errno == EAGAIN) {
      usleep(50);
      continue;
    }
    break;
  }
  exit(1);
}

typedef struct {
  pthread_mutex_t mu;
  pthread_cond_t cv;
  int state;
} event_t;

static void event_init(event_t* ev)
{
  if (pthread_mutex_init(&ev->mu, 0))
    exit(1);
  if (pthread_cond_init(&ev->cv, 0))
    exit(1);
  ev->state = 0;
}

static void event_reset(event_t* ev)
{
  ev->state = 0;
}

static void event_set(event_t* ev)
{
  pthread_mutex_lock(&ev->mu);
  if (ev->state)
    exit(1);
  ev->state = 1;
  pthread_mutex_unlock(&ev->mu);
  pthread_cond_broadcast(&ev->cv);
}

static void event_wait(event_t* ev)
{
  pthread_mutex_lock(&ev->mu);
  while (!ev->state)
    pthread_cond_wait(&ev->cv, &ev->mu);
  pthread_mutex_unlock(&ev->mu);
}

static int event_isset(event_t* ev)
{
  pthread_mutex_lock(&ev->mu);
  int res = ev->state;
  pthread_mutex_unlock(&ev->mu);
  return res;
}

static int event_timedwait(event_t* ev, uint64_t timeout)
{
  uint64_t start = current_time_ms();
  uint64_t now = start;
  pthread_mutex_lock(&ev->mu);
  for (;;) {
    if (ev->state)
      break;
    uint64_t remain = timeout - (now - start);
    struct timespec ts;
    ts.tv_sec = remain / 1000;
    ts.tv_nsec = (remain % 1000) * 1000 * 1000;
    pthread_cond_timedwait(&ev->cv, &ev->mu, &ts);
    now = current_time_ms();
    if (now - start > timeout)
      break;
  }
  int res = ev->state;
  pthread_mutex_unlock(&ev->mu);
  return res;
}

struct thread_t {
  int created, call;
  event_t ready, done;
};

static struct thread_t threads[16];
static void execute_call(int call);
static int running;

static void* thr(void* arg)
{
  struct thread_t* th = (struct thread_t*)arg;
  for (;;) {
    event_wait(&th->ready);
    event_reset(&th->ready);
    execute_call(th->call);
    __atomic_fetch_sub(&running, 1, __ATOMIC_RELAXED);
    event_set(&th->done);
  }
  return 0;
}

static void execute_one(void)
{
  if (write(1, "executing program\n", sizeof("executing program\n") - 1)) {
  }
  int i, call, thread;
  for (call = 0; call < 11; call++) {
    for (thread = 0; thread < (int)(sizeof(threads) / sizeof(threads[0]));
         thread++) {
      struct thread_t* th = &threads[thread];
      if (!th->created) {
        th->created = 1;
        event_init(&th->ready);
        event_init(&th->done);
        event_set(&th->done);
        thread_start(thr, th);
      }
      if (!event_isset(&th->done))
        continue;
      event_reset(&th->done);
      th->call = call;
      __atomic_fetch_add(&running, 1, __ATOMIC_RELAXED);
      event_set(&th->ready);
      event_timedwait(&th->done, 50);
      break;
    }
  }
  for (i = 0; i < 100 && __atomic_load_n(&running, __ATOMIC_RELAXED); i++)
    sleep_ms(1);
}

static void execute_one(void);

#define WAIT_FLAGS 0

static void loop(void)
{
//  int iter = 0;
  for (;; /*iter++*/) {
    int pid = fork();
    if (pid < 0)
      exit(1);
    if (pid == 0) {
      execute_one();
      exit(0);
    }
    int status = 0;
    uint64_t start = current_time_ms();
    for (;;) {
      sleep_ms(10);
      if (waitpid(-1, &status, WNOHANG | WAIT_FLAGS) == pid)
        break;
      if (current_time_ms() - start < 5000)
        continue;
      kill_and_wait(pid, &status);
      break;
    }
  }
}

uint64_t r[4] = {0xffffffffffffffff, 0xffffffffffffffff, 0xffffffffffffffff,
                 0xffffffffffffffff};

void execute_call(int call)
{
  intptr_t res = 0;
  switch (call) {
  case 0:
    memcpy((void*)0x200000000200, "./file0\000", 8);
    res = syscall(SYS_openat, /*fd=*/0xffffff9c, /*file=*/0x200000000200ul,
                  /*flags=O_VERIFY|O_CREAT|O_CLOEXEC|O_WRONLY*/ 0x300201ul,
                  /*mode=S_IWGRP|S_IXUSR|S_IWUSR*/ 0xd0ul);
    if (res != -1)
      r[0] = res;
    break;
  case 1:
    *(uint32_t*)0x200000000240 = r[0];
    *(uint64_t*)0x200000000248 = 0x80000002;
    *(uint64_t*)0x200000000250 = 0x200000000080;
    memcpy((void*)0x200000000080, "\x1f\x9a\xc4", 3);
    *(uint64_t*)0x200000000258 = 3;
    *(uint32_t*)0x200000000260 = 0;
    *(uint32_t*)0x200000000264 = 0;
    *(uint64_t*)0x200000000268 = 0;
    *(uint32_t*)0x200000000270 = 0;
    *(uint32_t*)0x200000000274 = 0;
    *(uint64_t*)0x200000000278 = 0;
    *(uint64_t*)0x200000000280 = 7;
    *(uint64_t*)0x200000000288 = 0;
    *(uint32_t*)0x200000000290 = 0;
    *(uint32_t*)0x200000000294 = 0;
    *(uint64_t*)0x200000000298 = 0;
    *(uint64_t*)0x2000000002a0 = 0;
    *(uint64_t*)0x2000000002a8 = 0;
    syscall(SYS_aio_write, /*iocb=*/0x200000000240ul);
    break;
  case 2:
    syscall(SYS_mlockall, /*flags=MCL_FUTURE*/ 2ul);
    break;
  case 3:
    memcpy((void*)0x200000000100, "./file0\000", 8);
    res = syscall(SYS_open, /*file=*/0x200000000100ul,
                  /*flags=O_DIRECT*/ 0x10000ul, /*mode=*/0ul);
    if (res != -1)
      r[1] = res;
    break;
  case 4:
    *(uint64_t*)0x200000001780 = 0x200000000180;
    *(uint64_t*)0x200000001788 = 0x1b133353141e377d;
    syscall(SYS_preadv, /*fd=*/r[1], /*vec=*/0x200000001780ul,
            /*vlen=*/0x10000000000000d1ul, /*off=*/0ul);
    break;
  case 5:
    memcpy((void*)0x200000000040, "./file0\000", 8);
    syscall(
        SYS_open, /*file=*/0x200000000040ul,
        /*flags=O_TRUNC|O_NONBLOCK|O_NOFOLLOW|O_CREAT|O_APPEND|0x2*/ 0x70eul,
        /*mode=*/0ul);
    break;
  case 6:
    memcpy((void*)0x200000000480, "./file0\000", 8);
    res = syscall(
        SYS_open, /*file=*/0x200000000480ul,
        /*flags=O_NONBLOCK|O_CREAT|O_RDWR|0x80400000000000*/ 0x80400000000206ul,
        /*mode=*/0ul);
    if (res != -1)
      r[2] = res;
    break;
  case 7:
    syscall(SYS_mmap, /*addr=*/0x200000000000ul, /*len=*/0x200000ul,
            /*prot=PROT_WRITE|PROT_READ*/ 3ul,
            /*flags=MAP_FIXED|MAP_SHARED|0x20000*/ 0x20011ul, /*fd=*/r[2],
            /*offset=*/0ul);
    break;
  case 8:
    memcpy((void*)0x200000000040, "./file0\000", 8);
    syscall(SYS_truncate, /*file=*/0x200000000040ul, /*len=*/0xaa480ul);
    break;
  case 9:
    memcpy((void*)0x200000000480, "./file0\000", 8);
    res = syscall(SYS_open, /*file=*/0x200000000480ul, /*flags=*/0ul,
                  /*mode=*/0ul);
    if (res != -1)
      r[3] = res;
    break;
  case 10:
    syscall(SYS_mmap, /*addr=*/0x200000000000ul, /*len=*/0x200000ul,
            /*prot=PROT_WRITE|PROT_READ*/ 3ul,
            /*flags=MAP_FIXED|MAP_PRIVATE*/ 0x12ul, /*fd=*/r[3],
            /*offset=*/0ul);
    break;
  }
}
int main(void)
{
  syscall(SYS_mmap, /*addr=*/0x200000000000ul, /*len=*/0x1000000ul,
          /*prot=PROT_WRITE|PROT_READ|PROT_EXEC*/ 7ul,
          /*flags=MAP_FIXED|MAP_ANONYMOUS|MAP_PRIVATE*/ 0x1012ul,
          /*fd=*/(intptr_t)-1, /*offset=*/0ul);
  const char* reason;
  (void)reason;
  loop();
  return 0;
}
EOF
mycc -o /tmp/$prog -Wall -Wextra -O0 /tmp/$prog.c -lpthread || exit 1

(cd ../testcases/swap; ./swap -t 3m -i 30 -l 100 > /dev/null 2>&1) &
sleep 5

work=/tmp/$prog.dir
rm -rf $work
mkdir $work
cd /tmp/$prog.dir
for i in `jot 30`; do
	(
		mkdir d$i
		cd d$i
		timeout 3m /tmp/$prog > /dev/null 2>&1 &
	)
done
while pgrep -q $prog; do sleep 2; done
while pkill swap; do :; done
wait

rm -rf /tmp/$prog /tmp/$prog.c /tmp/$prog.core /tmp/$prog.?????? $work
exit 0
