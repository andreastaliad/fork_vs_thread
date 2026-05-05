// thread_recursive.c
// Create a recursive tree of pthreads to observe scalability and resource usage.
// Each thread creates `branch` child threads (if depth < max_depth), then joins them.
// Usage: thread_recursive [-b branch] [-d max_depth] [-s hold_seconds]

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include <errno.h>
#include <string.h>
#include <time.h>
#include <math.h>

typedef struct {
    int depth;
    int max_depth;
    int branch;
    int hold_seconds;
} tr_args_t;

static pthread_mutex_t count_mtx = PTHREAD_MUTEX_INITIALIZER;
static long total_created = 0;

static double now_wall(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

static void *thread_fn(void *varg) {
    tr_args_t args = *(tr_args_t *)varg;
    pthread_t *children = NULL;
    tr_args_t *children_args = NULL;

    if (args.depth >= args.max_depth) {
        sleep((unsigned)args.hold_seconds);
        return NULL;
    }

    children = calloc((size_t)args.branch, sizeof(pthread_t));
    if (!children) {
        perror("calloc");
        return NULL;
    }

    children_args = calloc((size_t)args.branch, sizeof(tr_args_t));
    if (!children_args) {
        perror("calloc");
        free(children);
        return NULL;
    }

    for (int i = 0; i < args.branch; ++i) {
        children_args[i].depth = args.depth + 1;
        children_args[i].max_depth = args.max_depth;
        children_args[i].branch = args.branch;
        children_args[i].hold_seconds = args.hold_seconds;

        int rc = pthread_create(&children[i], NULL, thread_fn, &children_args[i]);
        if (rc != 0) {
            fprintf(stderr, "pthread_create failed at depth %d (branch %d): %s\n",
                    args.depth, i, strerror(rc));
            children[i] = 0;
            break;
        }

        pthread_mutex_lock(&count_mtx);
        total_created++;
        pthread_mutex_unlock(&count_mtx);
        sched_yield();
    }

    for (int i = 0; i < args.branch; ++i) {
        if (children[i] == 0) continue;
        pthread_join(children[i], NULL);
    }

    free(children_args);
    free(children);
    return NULL;
}

static void usage(const char *p) {
    fprintf(stderr, "Usage: %s [-b branch] [-d max_depth] [-s hold_seconds]\n", p);
    fprintf(stderr, "Defaults: branch=2, max_depth=6, hold_seconds=30\n");
}

int main(int argc, char **argv) {
    int branch = 2;
    int max_depth = 6;
    int hold_seconds = 30;
    int opt;

    while ((opt = getopt(argc, argv, "b:d:s:h")) != -1) {
        switch (opt) {
        case 'b': branch = atoi(optarg); break;
        case 'd': max_depth = atoi(optarg); break;
        case 's': hold_seconds = atoi(optarg); break;
        case 'h':
        default: usage(argv[0]); return 1;
        }
    }

    if (branch < 1) branch = 1;
    if (max_depth < 0) max_depth = 0;
    if (hold_seconds < 0) hold_seconds = 0;

    printf("Thread recursive scaling: branch=%d, max_depth=%d, hold_seconds=%d\n",
           branch, max_depth, hold_seconds);

    double estimated = -1.0;
    if (branch == 1) {
        estimated = (double)(max_depth + 1);
    } else {
        double b = (double)branch;
        estimated = (pow(b, (double)(max_depth + 1)) - 1.0) / (b - 1.0);
    }

    printf("Estimated full-tree threads (including root): %.0f\n", estimated);

    double t0 = now_wall();

    pthread_t root;
    tr_args_t root_args = {0, max_depth, branch, hold_seconds};

    pthread_mutex_lock(&count_mtx);
    total_created = 1; // root counts as created
    pthread_mutex_unlock(&count_mtx);

    int rc = pthread_create(&root, NULL, thread_fn, &root_args);
    if (rc != 0) {
        fprintf(stderr, "Failed to create root thread: %s\n", strerror(rc));
        return 2;
    }

    pthread_join(root, NULL);

    double t1 = now_wall();

    printf("\nResult:\n");
    printf("  total_created_threads: %ld\n", total_created);
    printf("  wall_time: %.6fs\n", t1 - t0);
    printf("  estimated_full_tree: %.0f\n", estimated);
    return 0;
}
