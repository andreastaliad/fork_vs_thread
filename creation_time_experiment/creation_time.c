// creation_time.c
// Compare creation time of processes (fork) vs threads (pthreads).
// Measures wall-clock time and total CPU time (user+system, including children).

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <time.h>
#include <pthread.h>
#include <errno.h>

static double timespec_to_sec(const struct timespec *t) {
    return t->tv_sec + t->tv_nsec / 1e9;
}

static double timeval_to_sec(const struct timeval *t) {
    return t->tv_sec + t->tv_usec / 1e6;
}

// Get monotonic wall-clock time in seconds
static double now_wall(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return timespec_to_sec(&ts);
}

// Get total CPU time (self + children) in seconds using getrusage
static double now_cpu_total(void) {
    struct rusage ru_self, ru_children;
    getrusage(RUSAGE_SELF, &ru_self);
    getrusage(RUSAGE_CHILDREN, &ru_children);
    double self = timeval_to_sec(&ru_self.ru_utime) + timeval_to_sec(&ru_self.ru_stime);
    double children = timeval_to_sec(&ru_children.ru_utime) + timeval_to_sec(&ru_children.ru_stime);
    return self + children;
}

// Child process minimal work
static void child_work(void) {
    _exit(0);
}

// Thread minimal work
static void *thread_work(void *arg) {
    (void)arg;
    return NULL;
}

int run_fork_test(long iterations, double *out_wall, double *out_cpu) {
    double t0w = now_wall();
    double t0c = now_cpu_total();

    pid_t *children = calloc((size_t)iterations, sizeof(*children));
    if (children == NULL) {
        perror("calloc");
        return -1;
    }

    for (long i = 0; i < iterations; ++i) {
        pid_t pid = fork();
        if (pid < 0) {
            perror("fork");
            free(children);
            return -1;
        }
        if (pid == 0) {
            // Child does minimal work then exits
            child_work();
        } else {
            children[i] = pid;
        }
    }

    for (long i = 0; i < iterations; ++i) {
        // Parent reaps children after they have all been created.
        int status;
        while (waitpid(children[i], &status, 0) < 0) {
            if (errno == EINTR) continue;
            perror("waitpid");
            free(children);
            return -1;
        }
    }

    free(children);

    double t1w = now_wall();
    double t1c = now_cpu_total();

    *out_wall = t1w - t0w;
    *out_cpu = t1c - t0c;
    return 0;
}

int run_thread_test(long iterations, double *out_wall, double *out_cpu) {
    double t0w = now_wall();
    double t0c = now_cpu_total();

    pthread_t *threads = calloc((size_t)iterations, sizeof(*threads));
    if (threads == NULL) {
        perror("calloc");
        return -1;
    }

    for (long i = 0; i < iterations; ++i) {
        int rc = pthread_create(&threads[i], NULL, thread_work, NULL);
        if (rc != 0) {
            errno = rc;
            perror("pthread_create");
            free(threads);
            return -1;
        }
    }

    for (long i = 0; i < iterations; ++i) {
        int rc = pthread_join(threads[i], NULL);
        if (rc != 0) {
            errno = rc;
            perror("pthread_join");
            free(threads);
            return -1;
        }
    }

    free(threads);

    double t1w = now_wall();
    double t1c = now_cpu_total();

    *out_wall = t1w - t0w;
    *out_cpu = t1c - t0c;
    return 0;
}

static void usage(const char *prog) {
    fprintf(stderr, "Usage: %s [-n iterations]\n", prog);
    fprintf(stderr, "Defaults: iterations=1000\n");
}

int main(int argc, char **argv) {
    long iterations = 1000; // safe default
    int opt;
    while ((opt = getopt(argc, argv, "n:h")) != -1) {
        switch (opt) {
        case 'n': iterations = atol(optarg); break;
        case 'h':
        default:
            usage(argv[0]);
            return 1;
        }
    }

    if (iterations <= 0) iterations = 1000;

    printf("Creation time comparison: iterations=%ld\n", iterations);

    double wall_fork=0, cpu_fork=0;
    if (run_fork_test(iterations, &wall_fork, &cpu_fork) != 0) {
        fprintf(stderr, "fork test failed\n");
        return 2;
    }

    double wall_thread=0, cpu_thread=0;
    if (run_thread_test(iterations, &wall_thread, &cpu_thread) != 0) {
        fprintf(stderr, "thread test failed\n");
        return 3;
    }

    printf("\nResults (total):\n");
    printf("  fork  : wall=%.6fs, cpu=%.6fs, avg wall=%.3fus, avg cpu=%.3fus\n",
           wall_fork, cpu_fork, (wall_fork/iterations)*1e6, (cpu_fork/iterations)*1e6);
    printf("  thread: wall=%.6fs, cpu=%.6fs, avg wall=%.3fus, avg cpu=%.3fus\n",
           wall_thread, cpu_thread, (wall_thread/iterations)*1e6, (cpu_thread/iterations)*1e6);

    printf("\nNotes:\n");
    printf("- Wall time uses CLOCK_MONOTONIC. CPU time sums RUSAGE_SELF+RUSAGE_CHILDREN.\n");
    printf("- For fork(), child CPU time is counted via RUSAGE_CHILDREN.\n");
    return 0;
}
