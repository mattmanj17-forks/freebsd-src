#!/bin/sh

# panic: ../../../kern/uipc_usrreq.c:1256: uipc_sosend_stream_or_seqpacket: Empty stailq 0xfffffe00ffe5fc88->stqh_last is 0xfffffe00ffe5fcd0, not head's first field address
# cpuid = 5
# time = 1749593630
# KDB: stack backtrace:
# db_trace_self_wrapper() at db_trace_self_wrapper+0x2b/frame 0xfffffe00ffe5fab0
# vpanic() at vpanic+0x136/frame 0xfffffe00ffe5fbe0
# panic() at panic+0x43/frame 0xfffffe00ffe5fc40
# uipc_sosend_stream_or_seqpacket() at uipc_sosend_stream_or_seqpacket+0xa39/frame 0xfffffe00ffe5fd10
# sousrsend() at sousrsend+0x79/frame 0xfffffe00ffe5fd70
# dofilewrite() at dofilewrite+0x81/frame 0xfffffe00ffe5fdc0
# sys_writev() at sys_writev+0x69/frame 0xfffffe00ffe5fe00
# amd64_syscall() at amd64_syscall+0x169/frame 0xfffffe00ffe5ff30
# fast_syscall_common() at fast_syscall_common+0xf8/frame 0xfffffe00ffe5ff30
# --- syscall (0, FreeBSD ELF64, syscall), rip = 0x82330181a, rsp = 0x8238dbf68, rbp = 0x8238dbf90 ---
# KDB: enter: panic
# [ thread pid 4484 tid 101524 ]
# Stopped at      kdb_enter+0x33: movq    $0,0x122ebc2(%rip)
# db> x/s version
# version: FreeBSD 15.0-CURRENT #0 main-n277833-948078b65c27-dirty: Tue Jun 10 06:01:36 CEST 2025
# pho@mercat1.netperf.freebsd.org:/usr/src/sys/amd64/compile/PHO
# db> 

[ `id -u ` -ne 0 ] && echo "Must be root!" && exit 1

. ../default.cfg
set -u
prog=$(basename "$0" .sh)
cat > /tmp/$prog.c <<EOF
// https://syzkaller.appspot.com/bug?id=210ae0bfcef6324abfffbfaf10120b767106a990
// autogenerated by syzkaller (https://github.com/google/syzkaller)
// syzbot+cfcb8520b0071b548fba@syzkaller.appspotmail.com

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

static unsigned long long procid;

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
  for (call = 0; call < 5; call++) {
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
      if (call == 2)
        break;
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
  int iter = 0;
  for (;; iter++) {
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

uint64_t r[2] = {0xffffffffffffffff, 0xffffffffffffffff};

void execute_call(int call)
{
  intptr_t res = 0;
  switch (call) {
  case 0:
    res = syscall(SYS_socketpair, /*domain=*/1ul, /*type=SOCK_STREAM*/ 1ul,
                  /*proto=*/0, /*fds=*/0x200000000040ul);
    if (res != -1) {
      r[0] = *(uint32_t*)0x200000000040;
      r[1] = *(uint32_t*)0x200000000044;
    }
    break;
  case 1:
    memcpy((void*)0x200000000100, "\x09\x00\x10\x00", 4);
    syscall(SYS_setsockopt, /*fd=*/r[1], /*level=*/0, /*optname=*/3,
            /*optval=*/0x200000000100ul, /*optlen=*/4ul);
    break;
  case 2:
    *(uint64_t*)0x2000000018c0 = 0;
    *(uint32_t*)0x2000000018c8 = 0;
    *(uint64_t*)0x2000000018d0 = 0;
    *(uint64_t*)0x2000000018d8 = 0;
    *(uint64_t*)0x2000000018e0 = 0x200000001880;
    memcpy((void*)0x200000001880, "\x10\x00\x00\x00\xff\xff\x00\x00\x06", 9);
    *(uint64_t*)0x2000000018e8 = 0x10;
    *(uint32_t*)0x2000000018f0 = 0;
    syscall(SYS_sendmsg, /*fd=*/r[0], /*msg=*/0x2000000018c0ul, /*f=*/0ul);
    for (int i = 0; i < 64; i++) {
      syscall(SYS_sendmsg, /*fd=*/r[0], /*msg=*/0x2000000018c0ul, /*f=*/0ul);
    }
    break;
  case 3:
    syscall(SYS_writev, /*fd=*/r[0], /*vec=*/0ul, /*vlen=*/0ul);
    for (int i = 0; i < 64; i++) {
      syscall(SYS_writev, /*fd=*/r[0], /*vec=*/0ul, /*vlen=*/0ul);
    }
    break;
  case 4:
    syscall(SYS_setsockopt, /*fd=*/(intptr_t)-1, /*level=*/0, /*optname=*/0xa,
            /*optval=*/0ul, /*optlen=*/0ul);
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
  for (procid = 0; procid < 4; procid++) {
    if (fork() == 0) {
      loop();
    }
  }
  sleep(1000000);
  return 0;
}
EOF
mycc -o /tmp/$prog -Wall -Wextra -O0 /tmp/$prog.c -lpthread || exit 1

work=/tmp/$prog.dir
rm -rf $work
mkdir $work
cd /tmp/$prog.dir
timeout 3m /tmp/$prog > /dev/null 2>&1

rm -rf /tmp/$prog /tmp/$prog.c /tmp/$prog.core /tmp/$prog.?????? $work
exit 0
