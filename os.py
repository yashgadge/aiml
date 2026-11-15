#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Offline OS practical runner, paper guide, and viva explainer. Python 3.8+."""
import argparse
from collections import deque
import errno
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time

TITLES = {
    1: "Address book (Bash)",
    2: "Processes and sorting",
    3: "Producer-consumer",
    4: "Dining philosophers",
    5: "Banker's algorithm",
    6: "Named pipes (FIFO)",
    7: "Unnamed pipes",
    8: "Disk scheduling",
}
FILES = {
    1: ("practical1.sh",), 2: ("practical2.c",), 3: ("practical3.c",),
    4: ("practical4.c",), 5: ("practical5.c",), 6: ("process1.c", "process2.c"),
    7: ("practical7.c",), 8: ("practical8.c",),
}

# All paths and input commands go through argv. The shell program itself is fixed.
RUNNER = r"""
number=$1
mode=$2
windows_folder=$3
if [[ -n $windows_folder ]]; then
    folder=$(wslpath -u "$windows_folder") &&
        cd -- "$folder" || { echo "WSL cannot enter this folder. Try a local C: drive folder mounted in WSL." >&2; exit 73; }
fi

required=(mktemp rm rmdir chmod)
compiler=''
case "$number" in
    1) required+=(bash awk cat mv); packages='bash mawk coreutils' ;;
    6) required+=(mkfifo); packages='coreutils' ;;
    *) packages='coreutils' ;;
esac
if [[ $mode == sample ]]; then required+=(timeout); fi
missing=()
for tool in "${required[@]}"; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [[ $number != 1 ]]; then
    for candidate in gcc cc clang /usr/bin/gcc-[0-9]*; do
        if command -v "$candidate" >/dev/null 2>&1; then
            compiler=$candidate
            break
        fi
    done
    if [[ -z $compiler ]]; then
        missing+=('gcc/cc/clang')
        packages="build-essential $packages"
    fi
fi
if (( ${#missing[@]} )); then
    printf 'Missing Linux tools: %s\n' "${missing[*]}" >&2
    printf 'Offline, with all packages cached: sudo apt-get --no-download --no-remove install %s\n' "$packages" >&2
    printf 'If the cache is empty, use a prepared lab PC or matching packages from the lab admin.\n' >&2
    printf 'Later, with internet and permission: sudo apt-get update && sudo apt-get install %s\n' "$packages" >&2
    exit 127
fi

# Prefer Linux storage with execution enabled, even when the source is on a USB drive.
scratch=''
for parent in /tmp "${HOME:-/tmp}"; do
    scratch=$(mktemp -d -- "$parent/os-lab.XXXXXXXX" 2>/dev/null) || continue
    if [[ $number == 1 ]]; then break; fi
    if printf '#!/bin/sh\nexit 0\n' > "$scratch/probe" &&
        chmod u+x "$scratch/probe" && "$scratch/probe" >/dev/null 2>&1; then
        rm -f -- "$scratch/probe"
        break
    fi
    rm -f -- "$scratch/probe"
    rmdir -- "$scratch"
    scratch=''
done
if [[ -z $scratch ]]; then
    echo 'No writable build location that can run programs was found.' >&2
    echo 'Check space and permissions: df -h /tmp "$HOME"; ls -ld /tmp "$HOME"' >&2
    exit 73
fi
worker=''
cleanup() {
    if [[ -n $worker ]]; then
        kill "$worker" 2>/dev/null
        wait "$worker" 2>/dev/null
    fi
    rm -f -- "$scratch/run" "$scratch/process1" "$scratch/process2" \
        "$scratch/fifo1" "$scratch/fifo2"
    rmdir -- "$scratch"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

compile() {
    local target=$1 source=$2
    shift 2
    if [[ ! -r $source ]]; then
        printf 'Cannot read %s. Return to the assistant and save the selected practical again.\n' "$source" >&2
        return 66
    fi
    local output status=0 standard=c11
    output=$(LC_ALL=C "$compiler" -std="$standard" -Wall -Wextra -pedantic "$source" "$@" -o "$scratch/$target" 2>&1) || status=$?
    if (( status != 0 )) && [[ $output == *-std=c11* ]] &&
        [[ $output == *unrecognized* || $output == *unsupported* || $output == *invalid* || $output == *unknown* ]]; then
        echo 'Compiler does not accept C11. Retrying in C99 mode.' >&2
        standard=c99
        status=0
        output=$(LC_ALL=C "$compiler" -std="$standard" -Wall -Wextra -pedantic "$source" "$@" -o "$scratch/$target" 2>&1) || status=$?
    fi
    if (( status != 0 )) && [[ $number == 3 || $number == 4 ]] &&
        [[ $output == *'undefined reference'*sem_* ]]; then
        echo 'Retrying with the older semaphore library layout (-lrt).' >&2
        status=0
        output=$(LC_ALL=C "$compiler" -std="$standard" -Wall -Wextra -pedantic "$source" "$@" -lrt -o "$scratch/$target" 2>&1) || status=$?
    fi
    if (( status != 0 )); then
        printf '%s\n' "$output" >&2
        case "$output" in
            *'cannot find'*|*'stdio.h: No such file'*|*'pthread.h: No such file'*|*'cannot execute'*)
                echo 'The compiler, headers or linker are incomplete. Ubuntu: sudo apt install build-essential' >&2
                echo 'Offline cached install: sudo apt-get --no-download --no-remove install build-essential' >&2 ;;
            *'No space left on device'*)
                echo 'The build disk is full. Run df -h /tmp and free space or use another lab PC.' >&2 ;;
            *'Permission denied'*)
                echo 'Check read access to the source and write/execute access to /tmp.' >&2 ;;
            *)
                echo 'Read the first gcc error above. Compare the source with the assistant copy and check the indicated line.' >&2 ;;
        esac
        return 65
    fi
    [[ -z $output ]] || printf '%s\n' "$output" >&2
}

case "$number" in
    1) bash -n practical1.sh || exit 65 ;;
    3|4) compile run "practical$number.c" -pthread || exit $? ;;
    6) compile process1 process1.c && compile process2 process2.c || exit $? ;;
    *) compile run "practical$number.c" || exit $? ;;
esac
if [[ $mode == check ]]; then
    echo 'Required commands found and source syntax/build check passed.'
    exit 0
fi
case "$number" in
    1) bash practical1.sh ;;
    6)
        mkfifo -- "$scratch/fifo1" "$scratch/fifo2" || {
            echo 'Could not create the named pipes. Check /tmp permissions and free space.' >&2
            exit 73
        }
        "$scratch/process2" "$scratch/fifo1" "$scratch/fifo2" &
        worker=$!
        if ! kill -0 "$worker" 2>/dev/null; then
            echo 'Process 2 could not start. Check whether /tmp allows Linux executables.' >&2
            exit 70
        fi
        "$scratch/process1" "$scratch/fifo1" "$scratch/fifo2"
        result=$?
        if (( result == 0 )); then
            wait "$worker"
            result=$?
            worker=''
        fi
        exit "$result"
        ;;
    *)
        case "$mode" in
            normal) "$scratch/run" ;;
            sample) timeout 5 "$scratch/run" ;;
            *) "$scratch/run" "$mode" ;;
        esac
        ;;
esac
"""


SOURCES = {
    "practical1.sh": r'''#!/usr/bin/env bash

file=addressbook.txt

update_record() {
    local action=$1 name temp status newname newphone newcity
    echo "Enter Name to $action:"
    IFS= read -r name || return

    if [[ ! -f $file ]]; then
        echo "Address book does not exist."
        return
    fi

    temp=$(mktemp ./addressbook.XXXXXX) || return
    # Match the literal name and the field separator, even if the name contains a dot.
    TARGET_NAME=$name awk '
        index($0, ENVIRON["TARGET_NAME"] " | ") == 1 { found = 1; next }
        { print }
        END { if (!found) exit 3 }
    ' "$file" > "$temp"
    status=$?
    if (( status != 0 )); then
        rm -f -- "$temp"
        if (( status == 3 )); then
            echo "Record not found."
        fi
        return
    fi

    if [[ $action == modify ]]; then
        if ! {
            echo "Enter New Name:"
            IFS= read -r newname &&
            echo "Enter New Phone Number:" &&
            IFS= read -r newphone &&
            echo "Enter New City:" &&
            IFS= read -r newcity &&
            printf '%s | %s | %s\n' "$newname" "$newphone" "$newcity" >> "$temp"
        }; then
            rm -f -- "$temp"
            return
        fi
    fi

    if mv -- "$temp" "$file"; then
        if [[ $action == modify ]]; then
            echo "Record modified successfully."
        else
            echo "Record deleted successfully."
        fi
    else
        rm -f -- "$temp"
    fi
}

while true; do
    echo "=========================="
    echo " ADDRESS BOOK MENU"
    echo "=========================="
    echo "1. Create"
    echo "2. View"
    echo "3. Insert"
    echo "4. Delete"
    echo "5. Modify"
    echo "6. Exit"
    echo "Enter your choice:"
    read -r choice || break

    case $choice in
        1)
            if > "$file"; then
                echo "Address book created successfully."
            fi
            ;;
        2)
            if [[ -f $file ]]; then
                echo "----- Address Book -----"
                cat -- "$file"
            else
                echo "Address book does not exist."
            fi
            ;;
        3)
            echo "Enter Name:"
            IFS= read -r name || break
            echo "Enter Phone Number:"
            IFS= read -r phone || break
            echo "Enter City:"
            IFS= read -r city || break
            if printf '%s | %s | %s\n' "$name" "$phone" "$city" >> "$file"; then
                echo "Record inserted successfully."
            fi
            ;;
        4) update_record delete ;;
        5) update_record modify ;;
        6)
            echo "Exiting..."
            break
            ;;
        *) echo "Invalid choice." ;;
    esac
done
''',
    "practical2.c": r'''#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <inttypes.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static void bubble_sort(int arr[], int n)
{
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - i - 1; j++) {
            if (arr[j] > arr[j + 1]) {
                int temp = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = temp;
            }
        }
    }
}

static void selection_sort(int arr[], int n)
{
    for (int i = 0; i < n - 1; i++) {
        int min = i;
        for (int j = i + 1; j < n; j++) {
            if (arr[j] < arr[min])
                min = j;
        }
        int temp = arr[i];
        arr[i] = arr[min];
        arr[min] = temp;
    }
}

static void display(const int arr[], int n)
{
    for (int i = 0; i < n; i++)
        printf("%d ", arr[i]);
    printf("\n");
}

static int wait_for_child(pid_t pid)
{
    int status;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) {
            perror("waitpid");
            return EXIT_FAILURE;
        }
    }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0
        ? EXIT_SUCCESS : EXIT_FAILURE;
}

static int demonstrate_zombie(void)
{
    pid_t child = fork();
    if (child < 0) {
        perror("fork");
        return EXIT_FAILURE;
    }
    if (child == 0)
        _exit(0);

    siginfo_t info;
    int result;
    do {
        result = waitid(P_PID, child, &info, WEXITED | WNOWAIT);
    } while (result < 0 && errno == EINTR);
    if (result < 0)
        perror("waitid");
    else
        printf("Zombie: child PID %jd has exited and is waiting to be reaped.\n",
               (intmax_t)info.si_pid);

    if (wait_for_child(child) != EXIT_SUCCESS || result < 0)
        return EXIT_FAILURE;
    printf("Parent reaped child PID %jd with waitpid().\n", (intmax_t)child);
    return EXIT_SUCCESS;
}

static int demonstrate_orphan(void)
{
    // Keep the main process alive until the orphan has printed its new PPID.
    int notification[2];
    if (pipe(notification) < 0) {
        perror("pipe");
        return EXIT_FAILURE;
    }

    pid_t parent = fork();
    if (parent < 0) {
        perror("fork");
        close(notification[0]);
        close(notification[1]);
        return EXIT_FAILURE;
    }
    if (parent == 0) {
        close(notification[0]);
        pid_t original_parent = getpid();
        pid_t child = fork();
        if (child < 0) {
            perror("fork");
            _exit(EXIT_FAILURE);
        }
        if (child > 0)
            _exit(EXIT_SUCCESS);

        struct timespec delay = {0, 10000000};
        pid_t current_parent;
        while ((current_parent = getppid()) == original_parent)
            nanosleep(&delay, NULL);
        printf("Orphan: child PID %jd changed PPID from %jd to %jd.\n",
               (intmax_t)getpid(), (intmax_t)original_parent,
               (intmax_t)current_parent);
        fflush(stdout);
        close(notification[1]);
        _exit(EXIT_SUCCESS);
    }

    close(notification[1]);
    int status = wait_for_child(parent);
    char unused;
    ssize_t result;
    do {
        result = read(notification[0], &unused, 1);
    } while (result < 0 && errno == EINTR);
    close(notification[0]);
    if (result < 0) {
        perror("read");
        return EXIT_FAILURE;
    }
    return status;
}

int main(int argc, char *argv[])
{
    if (argc == 2 && strcmp(argv[1], "zombie") == 0)
        return demonstrate_zombie();
    if (argc == 2 && strcmp(argv[1], "orphan") == 0)
        return demonstrate_orphan();
    if (argc != 1) {
        fprintf(stderr, "Usage: %s [zombie|orphan]\n", argv[0]);
        return EXIT_FAILURE;
    }

    int n;
    printf("Enter number of elements: ");
    fflush(stdout);
    if (scanf("%d", &n) != 1 || n <= 0 || (size_t)n > SIZE_MAX / sizeof(int)) {
        fprintf(stderr, "Enter a positive number of elements.\n");
        return EXIT_FAILURE;
    }

    int *arr = malloc((size_t)n * sizeof(*arr));
    if (arr == NULL) {
        perror("malloc");
        return EXIT_FAILURE;
    }

    printf("Enter integers:\n");
    fflush(stdout);
    for (int i = 0; i < n; i++) {
        if (scanf("%d", &arr[i]) != 1) {
            fprintf(stderr, "Expected %d integers.\n", n);
            free(arr);
            return EXIT_FAILURE;
        }
    }

    // Each process gets its own copy of the array and starts with empty output buffers.
    fflush(stdout);
    pid_t child = fork();
    if (child < 0) {
        printf("Fork failed.\n");
        free(arr);
        return EXIT_FAILURE;
    }

    if (child == 0) {
        printf("\nChild Process (PID = %jd)\n", (intmax_t)getpid());
        selection_sort(arr, n);
        printf("Sorted by Child (Selection Sort): ");
        display(arr, n);
        free(arr);
        return EXIT_SUCCESS;
    }

    bubble_sort(arr, n);
    if (wait_for_child(child) != EXIT_SUCCESS) {
        free(arr);
        return EXIT_FAILURE;
    }
    printf("\nParent Process (PID = %jd)\n", (intmax_t)getpid());
    printf("Sorted by Parent (Bubble Sort): ");
    display(arr, n);
    free(arr);
    printf("Child process completed.\n");
    return EXIT_SUCCESS;
}
''',
    "practical3.c": r'''#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <pthread.h>
#include <semaphore.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { BUFFER_SIZE = 5, ITEMS = 6 };

static int buffer[BUFFER_SIZE];
static sem_t empty, full;
static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;

static void wait_for_slot(sem_t *slots)
{
    while (sem_wait(slots) == -1) {
        if (errno != EINTR) {
            perror("sem_wait");
            exit(EXIT_FAILURE);
        }
    }
}

static void *producer(void *arg)
{
    (void)arg;
    for (int i = 0; i < ITEMS; i++) {
        wait_for_slot(&empty);
        pthread_mutex_lock(&mutex);
        buffer[i % BUFFER_SIZE] = i + 1;
        printf("Produced:%d\n", i + 1);
        pthread_mutex_unlock(&mutex);
        sem_post(&full);
    }
    return NULL;
}

static void *consumer(void *arg)
{
    (void)arg;
    for (int i = 0; i < ITEMS; i++) {
        wait_for_slot(&full);
        pthread_mutex_lock(&mutex);
        printf("Consumed:%d\n", buffer[i % BUFFER_SIZE]);
        pthread_mutex_unlock(&mutex);
        sem_post(&empty);
    }
    return NULL;
}

static void check_thread(int status)
{
    if (status != 0) {
        fprintf(stderr, "Thread error: %s\n", strerror(status));
        exit(EXIT_FAILURE);
    }
}

int main(void)
{
    pthread_t p, c;
    if (sem_init(&empty, 0, BUFFER_SIZE) < 0) {
        perror("sem_init");
        return EXIT_FAILURE;
    }
    if (sem_init(&full, 0, 0) < 0) {
        perror("sem_init");
        sem_destroy(&empty);
        return EXIT_FAILURE;
    }

    check_thread(pthread_create(&p, NULL, producer, NULL));
    check_thread(pthread_create(&c, NULL, consumer, NULL));
    check_thread(pthread_join(p, NULL));
    check_thread(pthread_join(c, NULL));

    sem_destroy(&empty);
    sem_destroy(&full);
    pthread_mutex_destroy(&mutex);
    return EXIT_SUCCESS;
}
''',
    "practical4.c": r'''#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <pthread.h>
#include <semaphore.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

enum { PHILOSOPHERS = 5 };

static sem_t forks[PHILOSOPHERS];
static sem_t room;

static void wait_for(sem_t *resource)
{
    while (sem_wait(resource) < 0) {
        if (errno != EINTR) {
            perror("sem_wait");
            exit(EXIT_FAILURE);
        }
    }
}

static void *philosopher(void *arg)
{
    int left = *(int *)arg;
    int right = (left + 1) % PHILOSOPHERS;
    int id = left + 1;

    for (;;) {
        printf("Philosopher %d is THINKING\n", id);
        sleep(1);

        wait_for(&room);
        wait_for(&forks[left]);
        printf("Philosopher %d picked LEFT fork %d\n", id, left + 1);

        wait_for(&forks[right]);
        printf("Philosopher %d picked RIGHT fork %d\n", id, right + 1);

        printf("Philosopher %d is EATING\n", id);
        sleep(2);

        sem_post(&forks[left]);
        sem_post(&forks[right]);
        printf("Philosopher %d finished EATING\n", id);

        sem_post(&room);
        sleep(1);
    }
    return NULL;
}

int main(void)
{
    pthread_t threads[PHILOSOPHERS];
    int ids[PHILOSOPHERS];
    setvbuf(stdout, NULL, _IOLBF, 0);

    // If at most four philosophers compete for forks, all five cannot hold
    // one fork and wait for the next at the same time.
    if (sem_init(&room, 0, PHILOSOPHERS - 1) < 0) {
        perror("sem_init");
        return EXIT_FAILURE;
    }
    for (int i = 0; i < PHILOSOPHERS; i++) {
        if (sem_init(&forks[i], 0, 1) < 0) {
            perror("sem_init");
            return EXIT_FAILURE;
        }
    }
    for (int i = 0; i < PHILOSOPHERS; i++) {
        ids[i] = i;
        int status = pthread_create(&threads[i], NULL, philosopher, &ids[i]);
        if (status != 0) {
            fprintf(stderr, "Thread error: %s\n", strerror(status));
            return EXIT_FAILURE;
        }
    }
    for (int i = 0; i < PHILOSOPHERS; i++)
        pthread_join(threads[i], NULL);

    return EXIT_SUCCESS;
}
''',
    "practical5.c": r'''#include <stdio.h>
#include <stdbool.h>

#define P 4 // Number of processes
#define R 3 // Number of resource types

// Function to check if the system is in a safe state
bool isSafeState(int available[R], int max[P][R], int allocation[P][R], int safeSequence[P]) {
    int need[P][R];
    int work[R];
    bool finish[P] = {false};

    // 1. Calculate the Need matrix: Need = Max - Allocation
    for (int i = 0; i < P; i++) {
        for (int j = 0; j < R; j++) {
            need[i][j] = max[i][j] - allocation[i][j];
        }
    }

    // 2. Initialize Work vector with Available resources
    for (int i = 0; i < R; i++) {
        work[i] = available[i];
    }

    int count = 0;
    // 3. Find a process whose needs can be satisfied by current Work
    while (count < P) {
        bool foundProcess = false;

        for (int p = 0; p < P; p++) {
            // Check if process is not finished yet
            if (!finish[p]) {
                bool canAllocate = true;

                // Check if Need <= Work for all resources
                for (int j = 0; j < R; j++) {
                    if (need[p][j] > work[j]) {
                        canAllocate = false;
                        break;
                    }
                }
                // If resources can be allocated, simulate completion
                if (canAllocate) {
                    for (int j = 0; j < R; j++) {
                        work[j] += allocation[p][j];
                    }
                    safeSequence[count++] = p;
                    finish[p] = true;
                    foundProcess = true;
                }
            }
        }

        // If no process could be safely executed in this iteration, system is unsafe
        if (!foundProcess) {
            return false;
        }
    }

    return true;
}

int main(void) {
    // Available instances of each resource type (A, B, C)
    int available[R] = {1, 1, 1};

    // Maximum demand of each process
    int max[P][R] = {
        {2, 2, 1}, // P0
        {2, 1, 2}, // P1
        {3, 2, 2}, // P2
        {1, 2, 1} // P3
    };

    // Resources currently allocated to each process
    int allocation[P][R] = {
        {1, 1, 0}, // P0
        {1, 0, 1}, // P1
        {1, 1, 1}, // P2
        {0, 1, 0}, // P3
    };
    int safeSequence[P];

    printf("--- Banker's Algorithm Deadlock Avoidance ---\n\n");

    if (isSafeState(available, max, allocation, safeSequence)) {
        printf("Result: The system is in a SAFE state.\n");
        printf("Safe Execution Sequence: ");
        for (int i = 0; i < P; i++) {
            printf("P%d", safeSequence[i]);
            if (i < P - 1) printf(" -> ");
        }
        printf("\n");
    } else {
        printf("Result: The system is in an UNSAFE state! (Deadlock danger)\n");
    }

    return 0;
}
''',
    "practical7.c": r'''#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

enum { BUFFER_SIZE = 1024 };

static int write_all(int fd, const void *data, size_t length)
{
    const char *next = data;
    while (length > 0) {
        ssize_t count = write(fd, next, length);
        if (count < 0 && errno == EINTR)
            continue;
        if (count <= 0)
            return -1;
        next += count;
        length -= (size_t)count;
    }
    return 0;
}

static int copy_file(int path_pipe, int result_pipe)
{
    FILE *input = fdopen(path_pipe, "r");
    if (input == NULL) {
        perror("fdopen");
        return EXIT_FAILURE;
    }
    char *filepath = NULL;
    size_t capacity = 0;
    ssize_t length = getdelim(&filepath, &capacity, '\0', input);
    fclose(input);
    if (length <= 0) {
        free(filepath);
        return EXIT_FAILURE;
    }

    int fd = open(filepath, O_RDONLY);
    free(filepath);
    if (fd < 0) {
        const char message[] = "Error: Could not open the specified file.";
        return write_all(result_pipe, message, sizeof message - 1) == 0
            ? EXIT_SUCCESS : EXIT_FAILURE;
    }

    char buffer[BUFFER_SIZE];
    ssize_t count;
    int status = EXIT_SUCCESS;
    for (;;) {
        count = read(fd, buffer, sizeof buffer);
        if (count < 0 && errno == EINTR)
            continue;
        if (count <= 0)
            break;
        if (write_all(result_pipe, buffer, (size_t)count) < 0) {
            perror("write");
            status = EXIT_FAILURE;
            break;
        }
    }
    if (count < 0) {
        perror("read");
        status = EXIT_FAILURE;
    }
    close(fd);
    return status;
}

int main(void)
{
    int pipe1[2];  // Parent to child: file pathname.
    int pipe2[2];  // Child to parent: file contents.
    if (pipe(pipe1) < 0) {
        perror("pipe1 creation failed");
        return EXIT_FAILURE;
    }
    if (pipe(pipe2) < 0) {
        perror("pipe2 creation failed");
        return EXIT_FAILURE;
    }

    pid_t child = fork();
    if (child < 0) {
        perror("fork failed");
        return EXIT_FAILURE;
    }
    if (child == 0) {
        close(pipe1[1]);
        close(pipe2[0]);
        int status = copy_file(pipe1[0], pipe2[1]);
        close(pipe2[1]);
        _exit(status);
    }

    close(pipe1[0]);
    close(pipe2[1]);
    char *filepath = NULL;
    size_t capacity = 0;
    printf("Parent Process: Enter the file pathname to read: ");
    fflush(stdout);
    ssize_t length = getline(&filepath, &capacity, stdin);
    int status = EXIT_SUCCESS;

    if (length < 0) {
        status = EXIT_FAILURE;
    } else {
        if (length > 0 && filepath[length - 1] == '\n')
            filepath[--length] = '\0';
        if (write_all(pipe1[1], filepath, (size_t)length + 1) < 0) {
            perror("write");
            status = EXIT_FAILURE;
        }
    }
    free(filepath);
    close(pipe1[1]);

    // Drain the pipe before waiting so a large file cannot block both processes.
    if (status == EXIT_SUCCESS) {
        printf("\n--- Content received from Child Process ---\n");
        char buffer[BUFFER_SIZE];
        for (;;) {
            ssize_t count = read(pipe2[0], buffer, sizeof buffer);
            if (count < 0 && errno == EINTR)
                continue;
            if (count <= 0) {
                if (count < 0) {
                    perror("read");
                    status = EXIT_FAILURE;
                }
                break;
            }
            if (fwrite(buffer, 1, (size_t)count, stdout) != (size_t)count) {
                status = EXIT_FAILURE;
                break;
            }
        }
        printf("\n------------------------------------------\n");
    }
    close(pipe2[0]);

    int child_status;
    pid_t waited;
    do {
        waited = waitpid(child, &child_status, 0);
    } while (waited < 0 && errno == EINTR);
    if (waited < 0) {
        perror("waitpid");
        return EXIT_FAILURE;
    }
    if (!WIFEXITED(child_status) || WEXITSTATUS(child_status) != 0)
        return EXIT_FAILURE;
    return status;
}
''',
    "practical8.c": r'''#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

enum { MAX_REQUESTS = 100 };

static long long distance_between(int a, int b)
{
    return llabs((long long)a - b);
}

static void sstf(const int requests[], int n, int head)
{
    int done[MAX_REQUESTS] = {0};
    long long seek = 0;
    int current = head;
    printf("\nSSTF: %d", head);

    for (int i = 0; i < n; i++) {
        long long shortest = LLONG_MAX;
        int next = -1;
        for (int j = 0; j < n; j++) {
            long long distance = distance_between(requests[j], current);
            if (!done[j] && distance < shortest) {
                shortest = distance;
                next = j;
            }
        }

        done[next] = 1;
        seek += shortest;
        current = requests[next];
        printf(" -> %d", current);
    }
    printf("\nTotal seek time = %lld\n", seek);
}

static void move_to(int cylinder, int *current, long long *seek)
{
    *seek += distance_between(cylinder, *current);
    *current = cylinder;
    printf(" -> %d", cylinder);
}

static void scan(const int requests[], int n, int head, int max)
{
    long long seek = 0;
    int current = head;
    printf("\nSCAN: %d", head);

    for (int i = 0; i < n; i++) {
        if (requests[i] >= head)
            move_to(requests[i], &current, &seek);
    }
    move_to(max, &current, &seek);
    for (int i = n - 1; i >= 0; i--) {
        if (requests[i] < head)
            move_to(requests[i], &current, &seek);
    }
    printf("\nTotal seek time = %lld\n", seek);
}

static void clook(const int requests[], int n, int head)
{
    long long seek = 0;
    int current = head;
    printf("\nC-LOOK: %d", head);

    for (int i = 0; i < n; i++) {
        if (requests[i] >= head)
            move_to(requests[i], &current, &seek);
    }
    for (int i = 0; i < n; i++) {
        if (requests[i] < head)
            move_to(requests[i], &current, &seek);
    }
    printf("\nTotal seek time = %lld\n", seek);
}

static int compare_ints(const void *first, const void *second)
{
    int a = *(const int *)first;
    int b = *(const int *)second;
    return (a > b) - (a < b);
}

int main(void)
{
    int requests[MAX_REQUESTS], n, head, max;
    printf("Enter number of requests: ");
    if (scanf("%d", &n) != 1 || n < 1 || n > MAX_REQUESTS) {
        fprintf(stderr, "Enter a request count from 1 to %d.\n", MAX_REQUESTS);
        return EXIT_FAILURE;
    }

    printf("Enter request queue: ");
    for (int i = 0; i < n; i++) {
        if (scanf("%d", &requests[i]) != 1) {
            fprintf(stderr, "Expected %d cylinder numbers.\n", n);
            return EXIT_FAILURE;
        }
    }

    printf("Enter initial head position: ");
    if (scanf("%d", &head) != 1 || head < 0) {
        fprintf(stderr, "Enter a nonnegative head position.\n");
        return EXIT_FAILURE;
    }

    printf("Enter maximum cylinder number: ");
    if (scanf("%d", &max) != 1 || max < head) {
        fprintf(stderr, "The maximum cylinder must be at least the head position.\n");
        return EXIT_FAILURE;
    }
    for (int i = 0; i < n; i++) {
        if (requests[i] < 0 || requests[i] > max) {
            fprintf(stderr, "Requests must be between 0 and %d.\n", max);
            return EXIT_FAILURE;
        }
    }

    sstf(requests, n, head);
    qsort(requests, (size_t)n, sizeof(requests[0]), compare_ints);
    scan(requests, n, head, max);
    clook(requests, n, head);
    return EXIT_SUCCESS;
}
''',
    "process1.c": r'''#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

int main(int argc, char *argv[])
{
    if (argc != 1 && argc != 3) {
        fprintf(stderr, "Usage: %s [fifo1 fifo2]\n", argv[0]);
        return EXIT_FAILURE;
    }
    const char *fifo1 = argc == 3 ? argv[1] : "fifo1";
    const char *fifo2 = argc == 3 ? argv[2] : "fifo2";
    char *input = NULL;
    size_t capacity = 0;
    int status = EXIT_SUCCESS;

    printf("--- Process 1 Started ---\n");
    for (;;) {
        printf("\nEnter a sentence (or type 'exit' to quit): \n> ");
        fflush(stdout);
        ssize_t length = getline(&input, &capacity, stdin);
        const char *sentence = "exit";
        if (length >= 0) {
            while (length > 0 && (input[length - 1] == '\n' || input[length - 1] == '\r'))
                input[--length] = '\0';
            sentence = input;
        }

        FILE *out = fopen(fifo1, "w");
        if (out == NULL) {
            perror("Error opening fifo1 for writing");
            status = EXIT_FAILURE;
            break;
        }
        int written = fprintf(out, "%s\n", sentence);
        if (fclose(out) == EOF || written < 0) {
            perror("Error writing to fifo1");
            status = EXIT_FAILURE;
            break;
        }
        if (strcmp(sentence, "exit") == 0)
            break;

        FILE *in = fopen(fifo2, "r");
        if (in == NULL) {
            perror("Error opening fifo2 for reading");
            status = EXIT_FAILURE;
            break;
        }

        printf("\n[Process 1] Received Analysis Report:\n");
        char buffer[1024];
        size_t count;
        while ((count = fread(buffer, 1, sizeof buffer, in)) > 0)
            fwrite(buffer, 1, count, stdout);
        if (ferror(in)) {
            perror("Error reading fifo2");
            status = EXIT_FAILURE;
        }
        fclose(in);
        if (status != EXIT_SUCCESS)
            break;
    }

    free(input);
    printf("Process 1 terminating. \n");
    return status;
}
''',
    "process2.c": r'''#define _POSIX_C_SOURCE 200809L
#include <ctype.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

static void analyze_text(const char *text, size_t *chars, size_t *words, size_t *lines)
{
    bool in_word = false;
    *chars = strlen(text);
    *words = 0;
    *lines = *chars > 0;
    for (size_t i = 0; i < *chars; i++) {
        unsigned char ch = (unsigned char)text[i];
        if (ch == '\n')
            (*lines)++;
        if (isspace(ch)) {
            in_word = false;
        } else if (!in_word) {
            in_word = true;
            (*words)++;
        }
    }
}

static void write_report_and_send(const char *text, FILE *out)
{
    size_t chars, words, lines;
    analyze_text(text, &chars, &words, &lines);

    FILE *report = fopen("report.txt", "w+");
    if (report == NULL) {
        perror("Error opening file");
        return;
    }
    int written = fprintf(report,
                          " ------------------------- \n"
                          "Original Text: %s \n"
                          "Total Characters: %zu \n"
                          "Total Words     : %zu \n"
                          "Total Lines     : %zu \n"
                          " ------------------------- \n",
                          text, chars, words, lines);
    if (written < 0 || fflush(report) == EOF || fseek(report, 0, SEEK_SET) < 0) {
        perror("Error saving report.txt");
        fclose(report);
        return;
    }

    char buffer[1024];
    size_t count;
    while ((count = fread(buffer, 1, sizeof buffer, report)) > 0) {
        if (fwrite(buffer, 1, count, out) != count) {
            perror("Error writing fifo2");
            break;
        }
    }
    if (ferror(report))
        perror("Error reading report.txt");
    fclose(report);
}

int main(int argc, char *argv[])
{
    if (argc != 1 && argc != 3) {
        fprintf(stderr, "Usage: %s [fifo1 fifo2]\n", argv[0]);
        return EXIT_FAILURE;
    }
    const char *fifo1 = argc == 3 ? argv[1] : "fifo1";
    const char *fifo2 = argc == 3 ? argv[2] : "fifo2";
    char *input = NULL;
    size_t capacity = 0;
    int status = EXIT_SUCCESS;

    printf("--- Process 2 Started (Waiting for data...) ---\n");
    fflush(stdout);
    for (;;) {
        FILE *in = fopen(fifo1, "r");
        if (in == NULL) {
            perror("Error opening fifo1 for reading");
            status = EXIT_FAILURE;
            break;
        }
        ssize_t length = getline(&input, &capacity, in);
        fclose(in);
        if (length < 0)
            break;
        if (length > 0 && input[length - 1] == '\n')
            input[length - 1] = '\0';
        if (strcmp(input, "exit") == 0)
            break;

        FILE *out = fopen(fifo2, "w");
        if (out == NULL) {
            perror("Error opening fifo2 for writing");
            status = EXIT_FAILURE;
            break;
        }
        write_report_and_send(input, out);
        if (fclose(out) == EOF) {
            perror("Error closing fifo2");
            status = EXIT_FAILURE;
            break;
        }
    }

    free(input);
    printf("Process 2 terminating. \n");
    return status;
}
''',
}


# Aim, theory, numbered method, sample, expected result, conclusion, viva.
PAPER = {
    1: (
        "Implement an address book using a Bash script with create, view, insert, delete, modify, and exit operations.",
        "A Bash script groups terminal commands into a program. A loop repeats the menu and case selects an operation. "
        "The address book is a local text file, with one Name | Phone | City record per line. A temporary file makes updates safer.",
        (
            "Set addressbook.txt as the data file. Repeat the menu until Exit or end of input.",
            "For Create, open the file with > to make an empty book. For View, check that it exists and display it using cat.",
            "For Insert, read the name, phone and city, then append one formatted record using >>.",
            "For Delete, copy every record except the matching literal name into a temporary file.",
            "For Modify, filter the old name, read the replacement, and append it to the temporary file.",
            "Move the temporary file over the book only after the update succeeds.",
        ),
        "Choose 1, then 3. Enter Asha Patil, 9876543210, and Pune on separate lines. Then choose 2.",
        "The view displays Asha Patil | 9876543210 | Pune. Choose 6 to exit.",
        "Bash control flow and text-file redirection implement a persistent address book.",
        (
            ("What is the difference between > and >>?", "> truncates or creates the file. >> appends or creates it."),
            ("Why quote a filename?", "Quotes keep whitespace and wildcard characters inside one argument."),
            ("Why use a temporary file?", "The original remains intact while the updated version is being prepared."),
        ),
    ),
    2: (
        "Demonstrate fork() and waitpid() with parent and child sorting, and show zombie and orphan states in separate modes.",
        "fork creates a child process with its own virtual address space. The parent and child initially see the same input values. "
        "Each sorts its own copy. A zombie has already exited but has not been collected. An orphan is alive after its original parent exits.",
        (
            "Read the integer count and the integers. Flush pending output before forking.",
            "Call fork. A negative return indicates failure. Zero takes the child branch; a positive PID takes the parent branch.",
            "The child sorts with Selection Sort, repeatedly choosing the smallest remaining value.",
            "The parent sorts with Bubble Sort, swapping adjacent values that are out of order.",
            "Collect the child using waitpid and display both sorted results and the completion message.",
            "In zombie mode, use waitid with WNOWAIT to observe the exited child, then reap it. In orphan mode, compare the live child's old and new parent PIDs.",
        ),
        "Enter 6, then 2 9 7 5 6 1. Run the optional zombie and orphan modes separately.",
        "Both processes print 1 2 5 6 7 9. Process IDs vary. The separate modes show a reaped child and reparenting.",
        "The program demonstrates process creation, independent address spaces, lifecycle states, and synchronization through a wait.",
        (
            ("What does fork return?", "0 to the child, the child's PID to the parent, and -1 to the caller on failure."),
            ("Why fflush before fork?", "Any pending stdio buffer is copied by fork. Flushing prevents two copies of the prompt."),
            ("Who adopts an orphan?", "A Linux subreaper can adopt it, or the init process for its PID namespace."),
            ("Why do zombies matter?", "The child no longer runs, but its exit information occupies a process-table entry until collected."),
        ),
    ),
    3: (
        "Solve the bounded-buffer producer-consumer problem using two counting semaphores and a mutex.",
        "The five-slot circular buffer is shared by two threads. empty counts free slots and full counts available items. "
        "The mutex serializes the short critical section that accesses the buffer.",
        (
            "Initialize empty to 5, full to 0, and initialize the mutex. Create the producer and consumer.",
            "Producer waits on empty, locks the mutex, writes the next item at i modulo 5, and prints it.",
            "Producer unlocks the mutex and posts full to advertise the new item.",
            "Consumer waits on full, locks the mutex, reads the next item at its own index modulo 5, and prints it.",
            "Consumer unlocks and posts empty. Repeat until both threads handle all six items.",
            "Join both threads, then destroy the synchronization objects.",
        ),
        "No input. Run the program once.",
        "Produced:1 through Produced:6 and Consumed:1 through Consumed:6. The two groups of lines can interleave.",
        "Counting semaphores enforce buffer limits and a mutex protects the shared data. Circular indexing safely reuses slots.",
        (
            ("Can a mutex replace both semaphores?", "It protects a shared operation, but does not count items or free slots. The threads would still need a way to wait for those conditions."),
            ("What does sem_wait do at zero?", "It blocks until a permit is available. With a positive count it takes one permit."),
            ("Why use i % 5?", "It wraps position 5 back to slot 0 so the sixth item can reuse the first slot safely."),
            ("Why wait before locking?", "A blocked thread should leave the mutex available so the other thread can change the buffer."),
        ),
    ),
    4: (
        "Demonstrate synchronization for five dining philosophers and prevent circular wait using a room semaphore.",
        "Every philosopher is a thread. A fork is represented by a semaphore initialized to one. Each philosopher needs two adjacent forks. "
        "A room semaphore initialized to four prevents all five from holding one fork and waiting for another together.",
        (
            "Initialize five fork semaphores to one and the room semaphore to four. Create five threads, with IDs displayed as 1 through 5.",
            "A philosopher thinks, then enters the room by waiting on room.",
            "Acquire the left fork, then the right fork at the next index modulo five.",
            "Eat after acquiring both forks. Release both forks and the room permit.",
            "Repeat. Use Ctrl+C to end the demonstration.",
        ),
        "No input. Let it run until you see THINKING, picked LEFT/RIGHT fork, EATING and finished EATING.",
        "Philosophers continue making progress and adjacent philosophers cannot use the same fork at the same time. The exact order varies.",
        "The room limit prevents circular wait in this arrangement. It does not promise that every waiting thread is scheduled fairly.",
        (
            ("How can deadlock occur with five permits?", "Each philosopher can hold their left fork and wait forever for the right fork held by a neighbor."),
            ("Does deadlock freedom imply starvation freedom?", "No. A particular philosopher could repeatedly lose access even while other philosophers complete meals."),
            ("Which deadlock condition is broken?", "The four-person room limit prevents a circular wait across all five forks in this acquisition order."),
        ),
    ),
    5: (
        "Use the Banker's safety algorithm to determine whether the current resource allocation is safe and find a safe sequence.",
        "Available gives unused resources, Allocation gives assigned resources, and Max records each process's greatest possible demand. "
        "Need is Max minus Allocation. A safe state has at least one order in which everyone can finish.",
        (
            "Read the fixed Available, Max, and Allocation values from the program. Compute Need for every process and resource type.",
            "Set Work to Available and every Finish flag to false.",
            "Find an unfinished process whose Need is at most Work for every resource type.",
            "Simulate its completion. Add its current Allocation to Work, mark it finished, and append it to the safe sequence.",
            "Repeat until all processes finish. If a full pass finds no eligible process, report unsafe.",
        ),
        "No keyboard input. The code uses four processes, three resource types, and Available = (1, 1, 1).",
        "The sample is SAFE. Safe Execution Sequence: P0 -> P1 -> P2 -> P3.",
        "The safety check decides whether the operating system can guarantee completion for the declared maximum claims.",
        (
            ("Is unsafe the same as deadlocked?", "No. Unsafe means a safe completion order cannot be guaranteed for the stated maximum claims."),
            ("Why add Allocation rather than Max to Work?", "The remaining Need was hypothetically borrowed from Work and returned. The net gain is only the resources that were already allocated."),
            ("Does this program grant a new request?", "It implements the safety check. A full Banker implementation tentatively applies a request, checks safety, then grants it or rolls it back."),
        ),
    ),
    6: (
        "Communicate between two independent processes using two named pipes and return a character, word, and line report.",
        "A FIFO is a named filesystem entry for a kernel byte stream. The first pipe sends a sentence from Process 1 to Process 2. "
        "The second sends the report back. report.txt keeps the latest completed analysis.",
        (
            "Create fifo1 and fifo2. Start Process 2 and Process 1. The assistant arranges this automatically.",
            "Process 1 reads a sentence and strips its line ending while keeping spaces and punctuation.",
            "Process 1 writes the sentence to fifo1. Process 2 reads it and checks whether it is the exit message.",
            "Count bytes, whitespace-delimited words and lines. Write the report to report.txt.",
            "Process 2 sends the report through fifo2. Process 1 reads and displays it.",
            "Repeat until exit or terminal EOF. Both programs terminate and the assistant cleans up its private FIFOs.",
        ),
        "Enter Hello world! This is a FIFO full-duplex test. Then enter exit.",
        "The report shows the text, 45 characters, 8 words, and 1 line. This example uses ASCII; non-ASCII characters may occupy multiple bytes.",
        "Two one-directional FIFO channels allow a request and response between separate processes.",
        (
            ("What is the difference between a FIFO and a regular file?", "A FIFO is a stream carried by the kernel. The pathname identifies the channel, but bytes are not stored like normal file contents."),
            ("Why two FIFOs?", "Each provides one direction in this design and keeps the request stream separate from the reply."),
            ("Why does opening a FIFO sometimes appear to hang?", "A blocking read or write open waits for the other endpoint to open the same FIFO."),
            ("What is a word here?", "One contiguous run of non-whitespace bytes. A punctuation mark next to a letter stays in that word."),
        ),
    ),
    7: (
        "Use two unnamed pipes to send a file pathname from a parent to its child and return the file contents.",
        "pipe creates a read and write descriptor. fork lets the child inherit both pipes. "
        "Pipes have finite capacity and provide a byte stream. Closing unused descriptors allows end of stream to be seen.",
        (
            "Create two pipes and fork the child.",
            "Close each unused pipe end in each branch.",
            "The parent reads the pathname and sends it with a terminating NUL byte on the first pipe, then closes its writer.",
            "The child reads the pathname, opens the file, and copies bytes through the second pipe. If the file cannot be opened, it returns a message.",
            "The parent drains the second pipe and displays the bytes. It calls waitpid after draining.",
            "Close remaining descriptors and terminate.",
        ),
        "Create test.txt with printf 'Hello from a pipe.\\n' > test.txt and enter test.txt at the program prompt.",
        "The parent displays Hello from a pipe. between the output headers. Relative paths are interpreted from the current working folder.",
        "The two inherited pipes carry a request and its data between related processes. Draining the reply before waiting prevents a large-file block.",
        (
            ("What is a file descriptor?", "A small process-local integer representing an open file or stream. pipe returns one for each end."),
            ("Why drain the pipe before waitpid?", "If the parent waits first and the pipe fills, the child blocks while writing and cannot exit."),
            ("When does read return zero on the pipe?", "Once the buffer is empty and every descriptor referring to its write end has been closed."),
        ),
    ),
    8: (
        "Compare disk scheduling using SSTF, SCAN, and C-LOOK and calculate total head movement.",
        "Requests are cylinder numbers. Seek distance in this exercise is the absolute difference between consecutive positions. "
        "SSTF selects the closest request. SCAN goes toward the high end then reverses. C-LOOK wraps from the last high request to the lowest pending request.",
        (
            "Read the number of requests, the queue, the starting head position, and the maximum cylinder. Validate the range.",
            "SSTF repeatedly selects the nearest unserved request, keeping input order for ties.",
            "Sort the queue by cylinder for the other algorithms.",
            "SCAN services requests at and above the head, reaches the maximum cylinder, then services lower requests in descending order.",
            "C-LOOK services requests at and above the head, then wraps to the lowest pending cylinder and resumes ascending order.",
            "Add the absolute movement for each printed transition. In this handout the C-LOOK wrap distance is counted.",
        ),
        "Enter 8. Queue: 25 65 43 98 57 89 102 10. Head: 57. Maximum cylinder: 199.",
        "Total seek distance: SSTF = 155, SCAN = 331, C-LOOK = 170. The program prints each full service path.",
        "Different scheduling strategies change both order and movement. SSTF saves movement on this sample, but selection behavior depends on workload.",
        (
            ("How does SCAN differ from LOOK?", "SCAN reaches a physical end before reversing in this exercise. LOOK reverses at the last request in that direction."),
            ("Could SSTF starve a distant request?", "Yes. If nearer requests keep arriving, the distant one may be postponed."),
            ("Why does 57 appear twice?", "The first 57 is the start position. The second is a request serviced there with zero movement."),
            ("Does total seek time mean milliseconds?", "Here it is total cylinder movement, used as a simplified measure. Physical seek time is device-dependent."),
        ),
    ),
}
MANUAL = {
    1: "bash practical1.sh",
    2: "gcc practical2.c -o practical2 && ./practical2",
    3: "gcc practical3.c -pthread -o practical3 && ./practical3",
    4: "gcc practical4.c -pthread -o practical4 && ./practical4",
    5: "gcc practical5.c -o practical5 && ./practical5",
    6: "Terminal 1: gcc process1.c -o process1 && gcc process2.c -o process2 && mkfifo fifo1 fifo2 && ./process2\n"
       "Terminal 2, in the same folder: ./process1\n"
       "Create the FIFOs once. If they already exist as FIFOs, start ./process2 directly after compiling.",
    7: "gcc practical7.c -o practical7 && ./practical7",
    8: "gcc practical8.c -o practical8 && ./practical8",
}


# Canonical term; aliases; answer. Aliases are matched as whole words.
GLOSSARY_TEXT = r"""
Operating system|os,kernel,operating system|The operating system manages processes, memory, files and devices. The kernel is its privileged core. User programs call it through system calls for operations such as creating a process or opening a file.
System call|system calls,syscall,system call|A controlled entry from a user program into the kernel. A C library wrapper such as read() normally provides a convenient way to invoke it. printf() is a library function that can eventually call write().
Command line|terminal,command line,console,tty|The terminal supplies keyboard input and displays output. Bash is a shell running inside it. Python or a C binary can run as a program launched from the shell. A GUI terminal window and a shell program are separate components.
Working directory|working directory,current folder,cwd,pwd,relative path,absolute path|Every process has a current directory. Relative filenames such as test.txt start there. Absolute Linux paths start at /. Type pwd to check your folder, ls to list it, and cd to move. Quote a path that contains spaces.
Bash script|bash,shell script,bash script,shebang,bin/bash|A text file containing shell commands. The first line #!/usr/bin/env bash tells Linux how to execute it when launched directly. bash practical1.sh explicitly starts Bash and only needs source read permission.
Redirection|redirection,redirect,truncate,append,stdout,standard output|A shell can direct output into a file. > creates or truncates; >> appends. Standard input is stream 0, normal output is stream 1, and error output is stream 2. A C program often accesses these through stdin, stdout and stderr.
Shell quotes|quote,quotes,quoting,expansion,wildcard,globbing|Double quotes allow expansion of values such as $file while keeping the resulting text together. Single quotes normally preserve characters literally. Quoting is important for spaces in filenames and user-entered text.
Shell read|read -r,ifs,shell read|Read a line into a shell variable. -r keeps backslashes literal; setting IFS= immediately before read preserves leading and trailing spaces. A failed read often means end of input.
Shell case and loop|case,esac,while true,do,done,menu,shell flow|case selects the first matching pattern. ;; ends that branch and esac closes the case. while true repeats the menu until break, exit, or a read that fails.
AWK and literal matching|awk,index,environ,literal match,regex,regular expression|AWK reads one record at a time, normally a line. index(text, target) returns a one-based starting position or 0. In the address book matching index == 1 on the name plus delimiter finds an exact literal name at the start; characters like . have no regex meaning.
Temporary file|mktemp,temp file,temporary file,mv|mktemp safely creates a fresh name. The address book builds the update in that file, then mv replaces the old file once the new contents are ready. Creating it in the same directory keeps the rename on the same filesystem.
File permissions|permission,permissions,chmod,executable,noexec|Read permission lets the program open source, write permission on a directory lets it create entries, and execute permission lets Linux run a binary. A noexec mount can block execution even with execute bits set. bash file.sh reads a script through Bash.
Compiler and linker|gcc,gcc command,compilation,compiler,linker,build-essential,pthread flag|GCC turns C source into machine code through preprocessing, compiling, assembly and linking. -o sets the executable name. -pthread supplies thread-related options during compilation and linking. Ubuntu's build-essential package provides the standard build toolchain.
Header file|header,include,stdio.h,unistd.h,pthread.h,semaphore.h,sys/wait.h|A header exposes declarations and constants. stdio.h declares printf and FILE, unistd.h declares POSIX calls such as fork/read/write, sys/wait.h exposes wait interfaces, and pthread.h and semaphore.h declare synchronization APIs.
Process and thread|process,processes,thread,threads,multithreading|A process has a virtual address space and its own resources. Threads of one process share that address space and many resources, while each has its own stack and registers. Shared data needs synchronization when a thread can modify it.
Concurrency and parallelism|concurrency,parallelism,concurrent,parallel,scheduling|Concurrency means several activities can make overlapping progress, even on one CPU through time sharing. Parallelism means activities actually run at the same instant on different execution units. Thread and process print order can depend on scheduling.
Process ID|pid,ppid,getpid,getppid,pid_t,process id|PID identifies a process in its PID namespace. PPID identifies its current parent. getpid() and getppid() query those IDs. Reparenting changes PPID while the child's PID stays the same.
fork()|fork|fork creates one child from the caller. It returns 0 in the child and the child's PID in the parent. -1 signals failure with no new child. Memory changes after fork are normally separate; open descriptors can still refer to the same kernel resources.
Copy-on-write|copy on write,cow,address space,virtual memory|Linux can initially share memory pages across fork. A write causes a private copy of that page where needed. This gives each process independent logical memory without eagerly copying every page.
waitpid()|wait,waitpid,wait_for_child,wifexited,wexitstatus,reap,reaping|waitpid waits for a selected child and retrieves a status. WIFEXITED checks for a normal exit before WEXITSTATUS reads the exit code. Successfully waiting on an exited child also releases its remaining process-table record.
waitid() and WNOWAIT|waitid,wnowait,wexited,siginfo_t|waitid reports the selected child's state. WEXITED selects exit events. WNOWAIT leaves that event available for a later wait. The zombie demo uses those flags, prints the child's PID, then reaps it with waitpid.
Zombie process|zombie,defunct|A zombie is a child that has already exited but whose status is still waiting to be collected. It has no executing program. Only the retained process record remains until the parent or later adopter waits.
Orphan process|orphan,reparent,adopt,subreaper,init|An orphan is a still-running child whose original parent has exited. A subreaper or init in its PID namespace can become its new parent. The demo detects the change by comparing old and new PPID values.
Buffered output|buffered output,fflush,setvbuf,line buffered,iolbf,_iolbf|Standard I/O can hold output in a user-space buffer. fflush(stdout) pushes pending output toward the underlying stream. Flushing before fork avoids duplicated prompts. Line buffering emits output when a newline is printed.
Exit and signals|exit,_exit,exit_success,exit_failure,sigint,sigterm,ctrl+c|A process returns an exit status. exit flushes C streams and runs exit handlers; _exit ends immediately without those handlers. Ctrl+C normally sends SIGINT to the foreground process group. SIGTERM is a conventional request to terminate.
Interrupted system call|eintr,errno,perror,interrupted system call|A blocking call can report EINTR after a signal interrupts it. Where appropriate the code retries. errno carries such error codes after failure, and perror translates the current number into a message. Check the return value first.
Bubble Sort|bubble sort,bubble_sort,adjacent swap|Compare neighbors and swap those in the wrong order. Each pass moves a largest remaining element toward the end. The implementation uses roughly O(n^2) comparisons and O(1) extra sorting storage.
Selection Sort|selection sort,selection_sort,minimum index|At each step find the smallest value in the unsorted part and exchange it with the first unsorted element. It uses O(n^2) comparisons and O(1) extra sorting storage.
Counting semaphore|semaphore,counting semaphore,sem_t,sem_init,sem_wait,sem_post,sem_destroy|A counting semaphore tracks permits. sem_wait takes one or blocks when none are available; sem_post releases one and can wake a waiter. sem_init with pshared = 0 shares it among threads of this process. Destroy it after threads finish.
Mutex|mutex,pthread_mutex_t,pthread_mutex_lock,pthread_mutex_unlock,lock,mutual exclusion|A mutex allows one thread at a time to enter a protected region. The locking thread normally unlocks it. It protects buffer access in Practical 3, while the semaphores enforce buffer capacity and item availability.
Critical section|critical section,shared data,shared buffer|A critical section reads or updates shared state that could otherwise be accessed incompatibly. Keep it short. Practical 3 acquires the mutex around storage access and the associated display.
Race condition|race condition,data race,unsynchronized|Program behavior can depend incorrectly on timing when concurrent operations use shared state without protection. In C, an unsynchronized conflicting memory access with at least one write is a data race and gives undefined behavior.
Producer-consumer|producer,consumer,producer consumer,bounded buffer,empty,full|The producer publishes items and the consumer removes them. empty counts free slots and full counts queued items. Start them at 5 and 0 for a five-slot empty buffer. Posting the opposite semaphore signals a change in availability.
Circular buffer|circular buffer,ring buffer,modulo,wraparound,buffer_size|A fixed array is reused cyclically. The expression i % BUFFER_SIZE turns a growing counter into a valid slot index. In a five-slot array index 5 wraps to 0. Semaphores ensure that slot is free before an overwrite.
Thread creation and joining|pthread_create,pthread_join,pthread_t,join,thread id|pthread_create starts a function in another thread and returns its thread handle through an argument. pthread_join waits for a joinable thread to finish. Join both workers before destroying synchronization objects they might use.
Dining philosophers|dining philosophers,philosopher,room semaphore,left fork,right fork|Five threads around a table each need two adjacent forks. Use one permit for each fork and at most four simultaneous fork contenders. The limit prevents an all-five circular wait. It does not guarantee fairness.
Deadlock|deadlock,circular wait,coffman conditions,hold and wait,no preemption|Deadlock means a group cannot progress because each participant waits for resources another group member holds. The four classic conditions are mutual exclusion, hold-and-wait, no preemption, and circular wait.
Starvation and fairness|starvation,fairness,bounded waiting|A participant starves if it is postponed indefinitely while others continue. Fairness is about how opportunities are assigned. A solution can eliminate deadlock without guaranteeing fairness.
Banker's algorithm|banker,bankers,banker's algorithm,bankers algorithm,safety algorithm|The safety check simulates completing one eligible process at a time. A full resource-request algorithm would tentatively grant a request, test safety, and either keep the allocation or undo it. This practical demonstrates the safety check.
Resource matrices|allocation,available,max,maximum demand,need,work,finish,resource matrix|Allocation is already assigned, Max is the upper limit, and Need = Max - Allocation. Available represents unused resources. Work starts as Available; Finish tracks simulated completion. After a completion, Work gains that process's existing Allocation.
Safe sequence|safe sequence,safe state,unsafe state,unsafe|A safe sequence is an order in which each process can satisfy its declared remainder and then release resources for later ones. An unsafe state has no such guaranteed order. It may still continue if the worst-case demands never occur.
Interprocess communication|ipc,interprocess communication,inter process communication|IPC lets independent processes exchange data or coordinate. This set uses pipes. Other OS mechanisms include shared memory, message queues, sockets and signals.
Named pipe (FIFO)|named pipe,fifo,mkfifo,fifo1,fifo2|A FIFO has a filesystem pathname and carries a first-in-first-out byte stream through the kernel. Unrelated processes can open it by name. A blocking open waits for the corresponding reader or writer.
Unnamed pipe|unnamed pipe,anonymous pipe,pipe,pipe1,pipe2|pipe() creates a pair with read end at index 0 and write end at index 1. Children can inherit the two ends from a parent. Close unused writers so readers can see end of stream.
Duplex communication|duplex,full duplex,half duplex,request response|Full duplex means both directions are possible simultaneously. Two pipes provide two independent directions. This program's request-response protocol sends one sentence and receives one reply before sending another.
File descriptor|file descriptor,fd,close,open,o_rdonly|A file descriptor is an integer reference to an open resource in a process. open returns a descriptor or -1; close releases that process's reference. O_RDONLY requests read-only access.
C streams|file *,fopen,fclose,fdopen,fread,fwrite,fseek,report.txt,stdio|FILE * is a C library stream with buffering. fopen opens a pathname; fdopen wraps an existing descriptor. fread and fwrite transfer bytes, fclose ends the stream, and fseek repositions a regular file. A FIFO itself cannot be sought.
Partial writes|partial write,write_all,write,short write,pipe capacity|write returns the amount actually accepted. write_all advances past bytes already written and retries until complete. A finite pipe can make a writer block when a reader is not draining it. Read the reply before waiting for its writer to exit.
Read and end of file|read,eof,end of file,ctrl+d|read returns a positive byte count, 0 at end of stream, or -1 on error. A pipe reaches EOF after all writer ends close and stored bytes are consumed. Ctrl+D on a blank Linux terminal line normally signals terminal end of input.
Input lines and delimiters|getline,getdelim,delimiter,nul,null terminator,newline|getline reads up to a newline and grows a buffer when needed. getdelim allows a custom delimiter, in this practical a NUL byte after the pathname. A C string itself ends at a NUL character, written as '\0'.
Character, byte and word counting|character count,bytes,word count,isspace,strlen,whitespace,encoding,utf-8|strlen counts bytes before the NUL terminator. isspace identifies whitespace; an unsigned char cast makes the argument valid. Count a word whenever the stream changes from whitespace to a non-whitespace run. UTF-8 characters may occupy several bytes each.
Pointers and arrays|pointer,array,dereference,address of,void *,argv,argc|An array stores elements in order. A pointer stores an address. &x obtains an address and *p accesses the pointed-to value. void * is a generic object pointer. argc counts command-line arguments and argv holds their strings.
Dynamic allocation|malloc,free,size_t,ssize_t,heap|malloc requests memory and returns its address, or NULL on failure. free releases it. size_t holds nonnegative sizes. ssize_t can also represent -1 to signal read-like operations failing.
Formatted input and output|scanf,printf,fprintf,format specifier,%d,%zu,%jd,%lld|printf substitutes values into a format. scanf writes parsed values to addresses and returns how many conversions succeeded. %d represents int, %zu size_t, %jd intmax_t, and %lld long long. A mismatch can cause undefined behavior.
Disk scheduling|disk scheduling,disk head,cylinder,seek,seek time,seek distance|A request targets a cylinder in this simplified rotating-disk model. Every move adds the absolute cylinder difference to the total. Real timing also depends on device mechanics, rotation and transfer, so the printed figure here is a movement measure.
SSTF|sstf,shortest seek time first,nearest request|Select the outstanding cylinder closest to the current head, then repeat from the new position. This code picks the earlier input item on equal distances. A far request may wait indefinitely under a stream of nearby requests.
SCAN|scan,elevator algorithm,scan disk|Serve requests in one direction, continue to the disk endpoint, reverse, and serve remaining ones. This practical starts toward the maximum. LOOK would reverse at the final request instead of visiting the physical endpoint.
C-LOOK|c-look,clook,c look,circular look,c-scan,look|C-LOOK serves in one direction, wraps between extreme requested cylinders, and continues in its original direction. It avoids physical endpoints unless requested. C-SCAN instead wraps between physical ends. This practical counts wrap movement.
qsort and comparator|qsort,compare_ints,comparator,sorting comparator|qsort sorts an array in place. The comparator returns a negative number for first < second, zero for equality, and a positive number for first > second. Comparing without a subtraction avoids possible integer overflow.
Overflow and bounds|overflow,integer overflow,array bounds,long long,llabs,llong_max|Array indices must stay inside the declared capacity. Arithmetic outside the supported range can overflow. The disk program bounds request count and uses long long for movement, because the sum can exceed the maximum int value.
WSL|wsl,wsl.exe,windows subsystem for linux,ubuntu on windows|WSL can host a Linux distribution on Windows. A Windows Python interpreter can show the study menu by itself. To run the Linux practicals on Windows, WSL needs an installed Linux distribution and the same Bash/GCC tools used in the lab.
""".strip()

TOPICS = {
    1: ("Bash script", "Working directory", "Redirection", "Shell quotes", "Shell read",
        "Shell case and loop", "AWK and literal matching", "Temporary file", "File permissions"),
    2: ("Process and thread", "System call", "Process ID", "fork()", "Copy-on-write", "waitpid()",
        "waitid() and WNOWAIT", "Zombie process", "Orphan process", "Buffered output", "Bubble Sort", "Selection Sort"),
    3: ("Producer-consumer", "Counting semaphore", "Mutex", "Critical section", "Race condition",
        "Circular buffer", "Thread creation and joining", "Concurrency and parallelism"),
    4: ("Dining philosophers", "Counting semaphore", "Deadlock", "Starvation and fairness",
        "Thread creation and joining", "Concurrency and parallelism"),
    5: ("Banker's algorithm", "Resource matrices", "Safe sequence", "Deadlock", "Starvation and fairness"),
    6: ("Interprocess communication", "Named pipe (FIFO)", "Duplex communication", "C streams",
        "Input lines and delimiters", "Character, byte and word counting", "Read and end of file"),
    7: ("Interprocess communication", "Unnamed pipe", "fork()", "File descriptor", "Partial writes",
        "Read and end of file", "Input lines and delimiters", "waitpid()"),
    8: ("Disk scheduling", "SSTF", "SCAN", "C-LOOK", "qsort and comparator", "Overflow and bounds"),
}


def configure_console():
    # Keep an interactive terminal's encoding. Pipes and redirected files use UTF-8.
    for stream, errors in ((sys.stdin, "replace"), (sys.stdout, "backslashreplace"),
                           (sys.stderr, "backslashreplace")):
        if hasattr(stream, "reconfigure"):
            encoding = stream.encoding if stream.isatty() else "utf-8"
            stream.reconfigure(encoding=encoding or "utf-8", errors=errors)


def read_prompt(prompt):
    try:
        return input(prompt)
    except EOFError:
        return None


def decode_text(data):
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return data.decode("utf-16", errors="replace")
    if b"\x00" in data[:100]:
        return data.decode("utf-16-le", errors="replace")
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError:
        return data.decode("cp1252", errors="replace")


RECOVERY = {
    "ubuntu": (
        "Ubuntu is the operating system on your college PCs. WSL is for running Linux inside Windows.",
        "1. Download the assistant before going offline and bring it on a USB drive.",
        "2. On the lab PC, copy the file into a writable folder under Home and open it there.",
        "   In Files, look for Properties > Permissions > Executable as Program, then Run as a Program.",
        "   If Files only opens the editor, open Terminal in that folder and start it with:",
        "     python3 os_practicals_assistant.py",
        "3. Choose Run a practical, then T to test all eight before the exam.",
        "4. Choose the practical number to save, compile, and run it.",
        "   If Python is missing, or the test reports missing Bash or a compiler, ask for a prepared lab PC.",
    ),
    "gcc": (
        "Find a Linux compiler: command -v gcc cc clang; gcc --version",
        "Offline, with the necessary packages cached:",
        "  sudo apt-get --no-download --no-remove install build-essential",
        "If your lab supplied all the matching .deb files, open that package folder:",
        "  sudo apt-get --no-download --no-remove install ./*.deb",
        "If headers or dependencies are missing from both places, use a prepared Ubuntu PC.",
        "Online later: sudo apt-get update && sudo apt-get install build-essential",
    ),
    "python": (
        "Find Python on Ubuntu: python3 --version    Windows: py -3 --version",
        "The assistant uses Python 3.8+. With cached Ubuntu packages:",
        "  sudo apt-get --no-download --no-remove install python3",
        "With an already saved Windows installer, open that installer. If Python is missing entirely,",
        "run the saved Bash/C sources manually on the lab PC. The assistant cannot start without Python.",
    ),
    "files": (
        "Check location and case-sensitive filenames: pwd; ls -l",
        "Check disk space and folder permissions: df -h . /tmp; ls -ld . /tmp",
        "For a read-only USB, copy the assistant into a writable folder under Home and open it there.",
        "For Practical 7, type a readable file's full path without shell quotes at the program prompt.",
    ),
    "encoding": (
        "Check that the downloaded file starts with a Python shebang: head -n 2 os_practicals_assistant.py",
        "If the first line is HTML or a GitHub page, use the original raw file or a saved offline copy.",
        "The assistant saves sources as UTF-8 with LF. For a manually edited file, choose UTF-8 and Unix/LF in your editor.",
        "Check syntax on Ubuntu: python3 -m py_compile os_practicals_assistant.py",
        "Run a Bash file with bash practical1.sh if the executable bit is missing.",
    ),
    "fifo": (
        "Use option 6 in the assistant to create private FIFOs and start both processes.",
        "For a manual run, use two terminals open in the same folder. Start ./process2 first, then ./process1.",
        "Check the endpoints: ls -l fifo1 fifo2    Both items should have p as the first character.",
        "If regular files already use those names, use a fresh local folder and run: mkfifo fifo1 fifo2",
        "Type exit in Process 1 to finish. For no output after a file-open error, use a writable local folder.",
    ),
}

PRACTICAL_RECOVERY = {
    1: "Create or insert before viewing. Match the literal saved name. Option 1 clears an existing address book.",
    2: "Enter the count alone, then exactly that many integers. PIDs change each run. Zombie and orphan are the 2Z and 2O selections.",
    3: "Keep -pthread on the compile command. If an older linker specifically cannot resolve sem_* symbols, append -lrt after the source.",
    4: "The demo runs continuously. Press Ctrl+C after the first meals. Thread messages can appear in different orders.",
    5: "This program uses fixed data and takes no input. The reference result is P0 -> P1 -> P2 -> P3.",
    6: "Wait for the sentence prompt. Use exit to finish both processes. Reports go to report.txt in the working folder.",
    7: r"Use a readable local file. Make one with: printf 'Hello from a pipe.\n' > test.txt    Then enter test.txt.",
    8: "Use 1 to 100 requests. Each cylinder and the head must be between zero and the stated maximum.",
}


def diagnose(raw, number=None):
    msg = raw.casefold()
    topic = msg.strip()
    if topic in {"linux", "lab", "ubuntu lab"}:
        topic = "ubuntu"
    if topic in RECOVERY:
        return RECOVERY[topic]
    if topic in {"wsl advanced", "windows setup", "wsl import"}:
        return wsl_recovery(advanced=True)
    if topic in {"wsl feature", "wsl virtualization", "wsl access"}:
        return wsl_recovery(topic.split()[-1], advanced=True)
    if topic in {"wsl", "windows", "wsl setup"} or any(text in msg for text in (
            "wsl_e_default_distro_not_found", "no installed distributions", "no linux distribution is installed")):
        return wsl_recovery()
    if any(code in msg for code in ("0x8007019e", "wsl_e_wsl_optional_component_required")):
        return wsl_recovery("feature")
    if any(code in msg for code in ("0x80370102", "hcs_e_hyperv_not_installed")):
        return wsl_recovery("virtualization")
    if re.fullmatch(r"[1-8]", topic):
        number = int(topic)
        steps = [PRACTICAL_RECOVERY[number], "Manual run: " + MANUAL[number], "Sample: " + PAPER[number][3]]
        if number in (2, 3, 4, 5, 7, 8):
            flags = " -pthread" if number in (3, 4) else ""
            steps.append(f"Older or alternative Linux compiler: cc -std=c99{flags} practical{number}.c -o practical{number} && ./practical{number}")
        if number == 6:
            steps.extend(RECOVERY["fifo"])
        return steps
    rules = (
        (("no space left", "disk full", "winerror 112"),
         "The disk is full. On Ubuntu run df -h . /tmp. Free space or choose another writable folder or lab PC."),
        (("read-only file system", "permission denied", "winerror 5", "operation not permitted", "access is denied"),
         "Check that this folder is writable. On Ubuntu run pwd, ls -ld . /tmp and mount. "
         "Try a folder under your home directory. If the binary cannot run from /tmp, show the error to the lab admin."),
        (("missing in linux", "gcc: command not found", "gcc is required", "cannot find -l",
          "undefined reference", "gcc: fatal error", "pthread_create", "stdio.h:", "pthread.h:"),
         "Compile on Linux with gcc, cc or clang. Keep -pthread for Practicals 3 and 4. "
         "With all dependencies cached: sudo apt-get --no-download --no-remove install build-essential."),
        (("unrecognized command-line option", "invalid value", "unknown argument", "unsupported option", "for loop initial"),
         "If the compiler rejects -std=c11, retry the same compile command with -std=c99. "
         "An installed cc or clang can also replace gcc."),
        (("wsl not", "wsl cannot", "wsl unavailable", "wsl.exe", "wsl_e_"),
         "WSL is the Windows way to run Linux. On the Ubuntu lab PC, open the assistant directly. "
         "For Windows setup only, choose D and enter wsl advanced."),
        (("libmingw", "cc1.exe", "mingw", "msvcrt", "dll was not found"),
         "This is a Windows C compiler problem. Open Ubuntu or WSL and use its Linux gcc. The assistant does not call MinGW."),
        (("temporary failure resolving", "could not resolve", "unable to fetch", "could not connect", "failed to fetch"),
         "APT could not reach a repository. If you are offline, try an already equipped lab PC or ask the lab admin for matching offline packages. "
         "On an online network try sudo apt update before installing."),
        (("unable to locate package", "no installation candidate", "dpkg was interrupted", "could not get lock"),
         "If another package manager is running, let it finish. Check sudo apt update output and ask the lab admin "
         "if repositories are unavailable or dpkg is interrupted."),
        (("unexpected token", "missing terminating", "expected ';'", "stray", "syntax error", "indentationerror"),
         "Compare the indicated line and the line above with a fresh assistant copy. Save as plain UTF-8 text with LF line endings."),
        (("bad interpreter", "^m", "\\r': command not found", "exec format error"),
         "For a Bash file, resave as UTF-8 with LF endings and use bash practical1.sh. "
         "For a binary, compile from source on this Ubuntu machine and run the new binary."),
        (("could not open the specified file", "no such file", "filenotfounderror", "cannot read", "path does not exist"),
         "Check pwd and ls. Use the exact filename and capitalization or type its absolute path. "
         "For Practical 7, try a local file you can read."),
        (("fifo already exists", "error opening fifo", "mkfifo:", "broken pipe", "hang", "blocked"),
         "For Practical 6 use Run to start both endpoints automatically. If running manually, both terminals must use the same folder, "
         "with real FIFOs and Process 2 started. For Practical 4, Ctrl+C stops the intentionally continuous demo."),
        (("address book does not exist", "record not found"),
         "For Practical 1 create or insert first. Delete and Modify match the exact stored name. Create clears the existing book."),
        (("invalid choice", "expected", "request count", "positive number", "nonnegative", "maximum cylinder"),
         "Check the input format in the paper notes. For a C integer prompt, use whole numbers separated by spaces or newlines."),
        (("segmentation fault", "core dumped", "aborted"),
         "Run from a fresh embedded source copy and retry the sample input. Note the practical, input, and first error. "
         "For an edited C file, use gcc warnings and check array bounds and pointers."),
        (("python: command not found", "python3: command not found", "python was not found", "py is not recognized"),
         "Ubuntu: check python3 --version in a terminal; if missing, sudo apt install python3. "
         "Windows: try py -3 --version or an existing Python 3 installation. The study file needs Python 3.8 or newer."),
        (("no terminal", "cannot open display", "cannot connect to display", "gnome-terminal"),
         "Stay in the current terminal and use --here with --run. An Ubuntu desktop terminal is optional."),
        (("cancelled", "interrupted", "keyboardinterrupt", "sigint"),
         "Ctrl+C stops the foreground program. This is the expected way to finish Dining Philosophers."),
    )
    matches = [answer for needles, answer in rules if any(needle in msg for needle in needles)]
    steps = matches[:2] or [
        "Read the first error and note what failed: saving, compiling, or running. "
        "Choose the practical under Run to check its dependencies and build, then try its sample input. "
        "For an unrecognized error, record the full text and ask the lab instructor or support."
    ]
    if number in PRACTICAL_RECOVERY:
        steps.append(PRACTICAL_RECOVERY[number])
    return steps


def save_sources(number, cwd):
    names = FILES[number]
    folder = cwd
    version = 0
    while True:
        if version:
            suffix = "" if version == 1 else f"_{version}"
            folder = cwd / f"os_practical_{number}{suffix}"
            try:
                folder.mkdir()
            except FileExistsError:
                if not folder.is_dir() or folder.is_symlink():
                    version += 1
                    continue
        conflict = False
        for name in names:
            path = folder / name
            if path.is_symlink() or (
                path.exists() and (not path.is_file() or path.read_bytes() != SOURCES[name].encode("utf-8"))
            ):
                conflict = True
                break
        if conflict:
            version += 1
            continue

        for name in names:
            path = folder / name
            data = SOURCES[name].encode("utf-8")
            try:
                with path.open("xb") as out:
                    out.write(data)
            except FileExistsError:
                if path.is_symlink() or not path.is_file() or path.read_bytes() != data:
                    conflict = True
                    break
        if not conflict:
            return folder
        version += 1


class WslUnavailable(RuntimeError):
    def __init__(self, cause, message):
        super().__init__(message)
        self.cause = cause


def wsl_recovery(cause="distribution", advanced=False):
    if not advanced:
        return (
            "WSL runs Linux inside Windows. Your Ubuntu lab PC already runs Linux.",
            "Bring this assistant to the lab, open it on Ubuntu, and choose Run a practical.",
            "Choose T on the Ubuntu PC to check all eight. For lab instructions, choose D and enter ubuntu.",
            "Only if you want Ubuntu inside Windows: choose D and enter wsl advanced.",
        )
    if cause == "feature":
        return (
            "If allowed, enable WSL in Windows Features or run this in administrator PowerShell, then restart.",
            "  dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart",
            "WSL 2 also needs Virtual Machine Platform and virtualization. If those are blocked, use the Ubuntu lab PC.",
        )
    if cause == "virtualization":
        return (
            "Check virtualization in Task Manager > Performance > CPU. Ask the lab admin if it is disabled.",
            "If permitted, enable Virtual Machine Platform in administrator PowerShell and restart.",
            "  dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart",
            "Offline alternative if Windows features cannot be enabled: use the Ubuntu lab PC.",
        )
    if cause == "access":
        return (
            "Check WSL in PowerShell: wsl --status",
            "List installed systems: wsl -l -v    Older WSL: wsl -l",
            "Open the installed Ubuntu app once. If it fails, choose D and paste its error code.",
            "Offline alternative: use the Ubuntu lab PC.",
        )
    return (
        "Windows setup only. Skip this on a computer already running Ubuntu.",
        "Check for an existing system in PowerShell: wsl -l -v    Older WSL: wsl -l",
        "Offline on Windows, if you already have a compatible Ubuntu .wsl file: double-click it to install.",
        "For an existing Ubuntu rootfs .tar, use a new local folder and the actual archive path:",
        r'  New-Item -ItemType Directory "$env:LOCALAPPDATA\UbuntuLab"',
        r'  wsl --import UbuntuLab "$env:LOCALAPPDATA\UbuntuLab" "D:\ubuntu-rootfs.tar"',
        "New-Item creates a folder on Windows. The import registers the Linux files from a tar archive",
        "you already have. Changing the paths does not download Ubuntu.",
        "Without an archive or installed Linux, use the lab PC. A fresh WSL distro may still need GCC.",
        "Later, with internet and permission: wsl --install -d Ubuntu",
    )


def wsl_names(result, legacy=False):
    if result.returncode:
        return []
    output = decode_text(result.stdout).lstrip("\ufeff")
    lines = [line.strip().lstrip("* ").strip() for line in output.splitlines()]
    if legacy:
        lines = [line.split(" (", 1)[0] for line in lines]
    return [name for name in lines if re.fullmatch(r"[\w.-]+", name)
            and not name.casefold().startswith("docker-desktop")]


def windows_backend():
    wsl = shutil.which("wsl.exe")
    if wsl is None:
        raise WslUnavailable("feature", "WSL is unavailable on this PC.")
    result = subprocess.run([wsl, "--list", "--quiet"], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=15, check=False)
    details = (decode_text(result.stderr) + decode_text(result.stdout)).casefold()
    if any(code in details for code in ("0x8007019e", "wsl_e_wsl_optional_component_required")):
        raise WslUnavailable("feature", "The Windows Subsystem for Linux feature is disabled.")
    if any(code in details for code in ("0x80370102", "hcs_e_hyperv_not_installed")):
        raise WslUnavailable("virtualization", "WSL 2 cannot start its virtual machine.")
    if any(text in details for text in ("wsl_e_default_distro_not_found", "no installed distributions",
                                        "no installed linux distributions", "no distributions installed")):
        raise WslUnavailable("distribution", "No Linux distribution is installed in WSL.")
    names = wsl_names(result)
    if not names and (result.returncode or "--quiet" in details):
        legacy = subprocess.run([wsl, "-l"], capture_output=True, timeout=15, check=False)
        names = wsl_names(legacy, legacy=True)
        if legacy.returncode:
            raise WslUnavailable("access", "Windows could not access WSL.")
    if not names:
        raise WslUnavailable("distribution", "No Linux distribution is installed in WSL.")
    distro = next((name for name in names if name.casefold().startswith("ubuntu")), names[0])
    return [wsl, "--distribution", distro, "--exec"]


def run_command(number, mode, folder):
    if sys.platform == "win32":
        prefix = windows_backend()
        target = str(folder)
        bash = "bash"
    elif sys.platform.startswith("linux"):
        prefix, target = [], ""
        bash = shutil.which("bash")
        if bash is None:
            raise RuntimeError("Linux Bash is missing. Ubuntu command: sudo apt install bash")
    else:
        raise RuntimeError("For running the OS exercises, use Ubuntu or Windows with WSL. Study and Save still work here.")
    return prefix + [bash, "-c", RUNNER, "os-lab", str(number), mode, target]


def run_program(number, mode, folder):
    if mode != "check" and number in (1, 6):
        datafile = folder / ("addressbook.txt" if number == 1 else "report.txt")
        if datafile.is_symlink() or (datafile.exists() and not datafile.is_file()):
            raise RuntimeError(f"{datafile} needs to be a regular file. Use a different working directory.")
    command = run_command(number, mode, folder)
    if mode == "check":
        result = subprocess.run(command, cwd=folder, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=45)
        report = decode_text(result.stdout)
        if report:
            print(report, end="" if report.endswith("\n") else "\n")
        if result.returncode:
            for tip in diagnose(report, number):
                print(tip)
        return result.returncode

    print(f"\nRunning Practical {number} from {folder}", flush=True)
    if number == 4:
        print("Press Ctrl+C to stop this continuous demonstration.", flush=True)
    if number == 6:
        print("Enter a sentence or type exit. The latest report is saved as report.txt.", flush=True)
    if number == 7:
        print("Enter a readable text-file path. Relative paths start in the folder shown above.", flush=True)
    # Leave stdin/stdout connected to the terminal. Keep the error text for offline diagnosis.
    errors = deque(maxlen=20)
    with subprocess.Popen(command, cwd=folder, stderr=subprocess.PIPE) as process:
        for line in process.stderr:
            message = decode_text(line)
            print(message, end="" if message.endswith("\n") else "\n", file=sys.stderr, flush=True)
            errors.append(message[:2000])
        rc = process.wait()
    if rc in (-signal.SIGINT, 130):
        print("Stopped with Ctrl+C.")
        return 0
    if rc != 0:
        print(f"\n  Recovery (exit status {rc})")
        detail = "".join(errors)
        if rc in (-signal.SIGSEGV, 139):
            detail += "\nsegmentation fault"
        for tip in diagnose(detail, number):
            print("  " + tip)
    return rc


def open_terminal(arguments, folder):
    interpreter = Path(sys.executable)
    if sys.platform == "win32" and interpreter.name.lower() == "pythonw.exe":
        interpreter = interpreter.with_name("python.exe")
    args = [str(interpreter), str(Path(__file__).resolve()), *arguments]
    if sys.platform == "win32":
        try:
            subprocess.Popen(args, cwd=folder, creationflags=subprocess.CREATE_NEW_CONSOLE)
            return True
        except OSError:
            return False
    elif sys.platform.startswith("linux") and (os.getenv("DISPLAY") or os.getenv("WAYLAND_DISPLAY")):
        for terminal, launch_args in (("gnome-terminal", ["--wait", "--"]),
                                      ("x-terminal-emulator", ["-e"])):
            executable = shutil.which(terminal)
            if executable is None:
                continue
            try:
                process = subprocess.Popen([executable] + launch_args + args, cwd=folder)
                time.sleep(0.25)
                if process.poll() in (None, 0):
                    return True
            except OSError:
                continue
    return False


def desktop_launch():
    if sys.platform == "win32":
        return sys.stdin is None
    if not sys.platform.startswith("linux") or not (os.getenv("DISPLAY") or os.getenv("WAYLAND_DISPLAY")):
        return False
    # The file manager normally supplies /dev/null. Leave redirected input alone.
    try:
        return (sys.stdout is None or not sys.stdout.isatty()) and (
            sys.stdin is None or os.path.samefile("/proc/self/fd/0", os.devnull)
        )
    except OSError:
        return False


def working_folder(current):
    if sys.platform != "win32":
        return current

    windows_dir = Path(os.environ.get("SystemRoot") or os.environ.get("WINDIR") or r"C:\Windows").resolve()
    for candidate in (current, Path(__file__).resolve().parent):
        location = candidate.resolve()
        if location != windows_dir and windows_dir not in location.parents:
            return candidate
    return Path.home()


def start_in_terminal(number, mode, folder):
    if sys.stdin.isatty() and sys.stdout.isatty():
        if sys.platform == "win32":
            windows_backend()  # Report absent WSL before opening another console.
        if open_terminal(["--run", str(number), "--mode", mode, "--child"], folder):
            print("Opened the practical in a new terminal.")
            return 0
    return run_program(number, mode, folder)


def report_exception(exc):
    if isinstance(exc, WslUnavailable):
        print("  Run unavailable", file=sys.stderr)
        print(f"  {exc}", file=sys.stderr)
        for step in wsl_recovery(exc.cause):
            print(f"  {step}", file=sys.stderr)
        return
    if isinstance(exc, subprocess.TimeoutExpired):
        print("The environment check timed out. Open Ubuntu or WSL, then try again.", file=sys.stderr)
        return
    if isinstance(exc, OSError) and exc.errno in (errno.EACCES, errno.EROFS, errno.ENOSPC):
        print(f"Cannot save or run here: {exc}", file=sys.stderr)
    else:
        print(f"Setup error: {exc}", file=sys.stderr)
    for tip in diagnose(str(exc)):
        print(tip, file=sys.stderr)


def clipboard_text():
    runners = []
    if sys.platform == "win32":
        runners.append(["powershell.exe", "-NoProfile", "-Command",
                        "[Console]::OutputEncoding=[Text.Encoding]::UTF8; Get-Clipboard -Raw"])
    elif sys.platform.startswith("linux"):
        if os.getenv("WAYLAND_DISPLAY"):
            runners.append(["wl-paste", "--no-newline"])
        if os.getenv("DISPLAY"):
            runners += [["xclip", "-selection", "clipboard", "-o"], ["xsel", "--clipboard", "--output"]]
    for command in runners:
        if shutil.which(command[0]):
            try:
                proc = subprocess.run(command, capture_output=True, timeout=3)
                if proc.returncode == 0 and proc.stdout:
                    return decode_text(proc.stdout)
            except (OSError, subprocess.TimeoutExpired):
                continue
    return ""


def expanded_input(text):
    cmd, _, argument = text.strip().partition(" ")
    if cmd.casefold() == "paste" and not argument:
        print("Paste one or many lines, then type END alone on a new line.")
        lines = []
        while True:
            line = read_prompt("")
            if line is None or line.strip() == "END":
                return "\n".join(lines)
            lines.append(line)
    if cmd.casefold() == "clip" and not argument:
        data = clipboard_text()
        if not data:
            print("Clipboard text is unavailable. Try paste, a line range, or file <path>.")
        return data
    if cmd.casefold() == "file" and argument:
        try:
            path = Path(argument.strip().strip("\"'")).expanduser()
            with path.open("rb") as stream:
                data = stream.read(1024 * 1024 + 1)
            if len(data) > 1024 * 1024:
                print("Choose a text file under 1 MB or paste a smaller section.")
                return ""
            return decode_text(data)
        except OSError as exc:
            report_exception(exc)
            return ""
    return text


CONCEPTS = {}
ALIASES = {}
for entry in GLOSSARY_TEXT.splitlines():
    title, aliases, answer = entry.split("|", 2)
    CONCEPTS[title] = answer
    ALIASES[title] = (title.casefold(),) + tuple(aliases.split(","))

SECTIONS = {
    "practical1.sh": (
        (1, "Shell startup and address-book filename"),
        (5, "Delete/modify a literal name using a temporary file"), (57, "The repeating menu and its operations"),
    ),
    "practical2.c": (
        (1, "POSIX headers"), (13, "Parent's Bubble Sort"), (26, "Child's Selection Sort"),
        (40, "Print sorted values"), (47, "Wait for and reap a child"), (60, "Observe a zombie before reaping"),
        (87, "Create an orphan and observe reparenting"), (141, "Parse mode, read input, fork, and run the two sorts"),
    ),
    "practical3.c": (
        (1, "Shared data, buffer capacity and synchronization"), (15, "Take a semaphore permit, retrying interruptions"),
        (25, "Producer stores items"), (39, "Consumer removes items"), (52, "Report POSIX thread errors"),
        (60, "Set up semaphores and threads, join and clean up"),
    ),
    "practical4.c": (
        (1, "Resources shared by the five threads"), (15, "Wait for a resource without losing an interrupted wait"),
        (25, "One philosopher thinks, obtains forks, eats, and releases resources"),
        (55, "Limit fork contenders to four, then run five philosophers"),
    ),
    "practical5.c": (
        (1, "Headers, process count, and resource-type count"), (8, "Calculate Need and initialize the safety simulation"),
        (22, "Find a process that can finish and release its allocation"),
        (53, "Report an unsafe state if a scan cannot make progress"),
        (63, "Fixed sample values and display of the result"),
    ),
    "process1.c": (
        (1, "POSIX setup"), (7, "Process 1 entry point and the FIFO filenames"),
        (19, "Read a sentence and send it through fifo1"), (47, "Read and display the reply from fifo2"),
        (67, "Free the line buffer and finish"),
    ),
    "process2.c": (
        (1, "Headers for stream I/O and text analysis"), (9, "Count bytes, words and lines"),
        (28, "Write the report file and copy it into the reply stream"),
        (65, "Process 2 receives requests and sends replies until exit"),
    ),
    "practical7.c": (
        (1, "Headers and buffer setting"), (12, "Write a complete message even when write() accepts only part"),
        (27, "Child reads the path and sends the requested bytes"),
        (74, "Create both pipes and fork"), (100, "Parent reads and sends the pathname"),
        (122, "Drain the reply before waiting for the child"), (146, "Wait and inspect the child's exit status"),
    ),
    "practical8.c": (
        (1, "Headers, capacity and distance calculation"), (12, "SSTF chooses the nearest request"),
        (38, "Record a move and print the next cylinder"),
        (45, "SCAN goes to the maximum cylinder and reverses"),
        (63, "C-LOOK wraps to the lowest pending request"),
        (80, "Compare two requests for sorting"), (87, "Read and validate inputs, then run the algorithms"),
    ),
}
LINE_RULES = (
    (r"^#!", "The shebang selects Bash when the script is launched directly."),
    (r"^#define\s+_POSIX_C_SOURCE", "Expose POSIX declarations in the system headers before they are included."),
    (r"^#include", "Include declarations and constants from this header so the C compiler can check their use."),
    (r"^#define|^enum", "Define a named compile-time value such as a buffer size or count."),
    (r"^(//|#\s)", "This comment is for the reader. It explains the intent of the surrounding block."),
    (r"waitid\(", "Inspect the child's exit event. With WNOWAIT, a later wait must still collect it."),
    (r"waitpid\(", "Wait for this child and obtain its exit status. An EINTR check lets the code retry."),
    (r"=\s*fork\(", "Make a child. The child receives zero and the parent receives the child's PID."),
    (r"_exit\(", "End the child immediately without flushing any duplicated stdio buffers or running exit handlers."),
    (r"getppid\(", "Read the current parent's PID. Comparing with the old parent shows reparenting."),
    (r"\bsem_init\(", "Set up the semaphore and its starting permit count. A zero pshared value means threads in this process use it."),
    (r"\bsem_wait\(|\bwait_for(_slot)?\(&", "Take one permit or block until it becomes available. In these examples the permit represents space, an item, a fork, or a room entry."),
    (r"\bsem_post\(", "Return or publish one permit so a waiting thread can continue."),
    (r"\bpthread_mutex_lock\(", "Enter the mutex-protected critical section. A competing thread waits if the lock is held."),
    (r"\bpthread_mutex_unlock\(", "Leave the critical section and let another thread acquire the mutex."),
    (r"\bpthread_create\(", "Start a worker thread using the supplied start function and an optional argument."),
    (r"\bpthread_join\(", "Wait until this worker exits before proceeding with shutdown."),
    (r"\bsem_destroy\(|\bpthread_mutex_destroy\(", "Release the synchronization object's resources after its users have finished."),
    (r"% (BUFFER_SIZE|PHILOSOPHERS)", "Modulo wraps the position back to the first slot/fork after the last one."),
    (r"\bbuffer\[", "Access an element in the array. In the producer-consumer code the index wraps at the capacity."),
    (r"\bneed\[.*=.*max\[.*-\s*allocation", "Calculate the remaining resource requirement for this process and resource type."),
    (r"\bneed\[.*>\s*work", "Reject this candidate on the current pass if it needs more than the simulated pool has."),
    (r"\bwork\[.*\+=\s*allocation", "Return the completed process's original allocation to the simulated pool."),
    (r"\bsafeSequence\[.*=", "Record a process in the order the safety simulation finds it can finish."),
    (r"\b(?:finish|foundProcess|canAllocate)\b.*=", "Update a control flag for the safety check, so it can identify eligible processes and detect progress."),
    (r"\bpipe\(", "Create read and write file descriptors for a byte stream. Linux assigns read to index 0 and write to index 1."),
    (r"\bclose\(", "Close this process's descriptor. Closing unused writer ends is needed for the reader to detect EOF."),
    (r"\bgetdelim\(", "Read up to the requested delimiter and grow the buffer if necessary. Here the sent pathname ends with a NUL."),
    (r"\bgetline\(", "Read a line, growing the buffer if needed. A negative result signals EOF or an input error."),
    (r"\bfflush\(|\bsetvbuf\(", "Control when buffered output is displayed. Flushing also avoids duplicating buffered text across fork."),
    (r"\bfopen\(|\bfdopen\(", "Open or wrap an I/O stream. A read/write mode determines what the program can do; opening a FIFO may wait for its other endpoint."),
    (r"\bfclose\(", "Close the library stream and flush any pending writes."),
    (r"\b(fread|fwrite|fseek)\(", "Read, write, or reposition a C stream. The arguments specify bytes, counts and which open stream to use."),
    (r"\bwrite(_all)?\(", "Send bytes to a file descriptor. write_all loops until every byte has been sent or an error occurs."),
    (r"\bread\(", "Retrieve bytes from the descriptor. Check the count for data, end of stream, or an error."),
    (r"\bisspace\(", "Test whether this byte is whitespace. Whitespace ends the current word."),
    (r"\bstrlen\(", "Measure the number of bytes before the terminating NUL in this C string."),
    (r"\bstrcmp\(", "Compare two C strings. A return of zero means their bytes match."),
    (r"\bmalloc\(", "Allocate the requested number of bytes dynamically. The pointer is checked before the allocation is used."),
    (r"\bfree\(", "Free the allocated buffer when it is no longer needed."),
    (r"\bf?printf\(", "Produce formatted output. Match the percent specifiers to argument types, and use \\n for a new line."),
    (r"\bscanf\(", "Parse input and store values at the supplied addresses. Check how many conversions succeeded."),
    (r"\bqsort\(", "Sort the request array once so SCAN and C-LOOK can traverse it in cylinder order."),
    (r"\bllabs\(", "Return the absolute distance after calculating it in a type wide enough to hold the difference."),
    (r"\bmove_to\(", "Add the movement to the seek total, update the current cylinder, and print the new position."),
    (r"\b(errno|perror)\b", "Check or report a reason for a failed system or library operation."),
    (r"\bmktemp\b", "Create a unique temporary file for changes before replacing the address book."),
    (r"\bmv\b", "Move the staged file into the address-book pathname only after its contents are ready."),
    (r"\bawk\b|\bENVIRON\b|\bindex\(", "Filter records by a literal name and field separator at the start of a line. Other records are copied unchanged."),
    (r"\bread -r\b", "Read keyboard input and keep backslashes literal. IFS= also keeps whitespace at the ends."),
    (r">>", "Append a record to the file without clearing earlier lines."),
    (r">\s*[\"$]", "Redirect output into the named file. A single > can create or truncate it."),
    (r"^\[\[|^if\b|^else\b|^fi\b", "Test a condition or select a branch. Read the condition together with the controlled operation."),
    (r"^(for|while|do)\b", "Repeat the block using the given condition or iteration. Check what value changes each time."),
    (r"^(case|esac|;;)", "Select or end one menu branch based on the user's current choice."),
    (r"^(return|exit|break|continue)\b", "Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration."),
    (r"^[{};]+$", "This punctuation opens or closes the enclosing block or ends a statement."),
    (r"\b(?:int|char|long|bool|ssize_t|size_t|FILE|sem_t|static|void)\b", "Declare a value or function used in this block. Initializers set the value used before the first update."),
    (r"=", "Set or update a value, or compare it when the operator is ==, !=, <= or >=."),
)

def show_paper(number):
    aim, theory, algorithm, sample, result, conclusion, viva = PAPER[number]
    print(f"\nPRACTICAL {number}  {TITLES[number]}")
    print("\nTitle and aim\n" + aim)
    print("\nRequirements\n" + ("Ubuntu, Bash, and a writable folder." if number == 1
                                else "Ubuntu, GCC, Bash, a terminal, and a writable folder."))
    print("\nTheory\n" + theory)
    print("\nAlgorithm")
    for i, step in enumerate(algorithm, 1):
        print(f"{i}. {step}")
    print("\nManual procedure\n" + MANUAL[number])
    print("\nProgram\nWrite the source with the filename(s) " + ", ".join(FILES[number]) + ".")
    print("\nSample input or observation steps\n" + sample)
    print("\nExpected output and result\n" + result)
    print("\nConclusion\n" + conclusion)
    print("\nViva practice")
    for question, answer in viva:
        print(f"Q. {question}\nA. {answer}\n")


def show_source(number, filename=None):
    for name in (filename,) if filename else FILES[number]:
        print(f"\n{name}")
        for i, line in enumerate(SOURCES[name].splitlines(), 1):
            print(f"{i:3}  {line}")


def describe_line(line):
    stripped = line.strip()
    if not stripped:
        return "Blank line separates related code. It has no runtime action."
    for pattern, explanation in LINE_RULES:
        if re.search(pattern, stripped):
            return explanation
    if stripped in {"then", "end", "done", "do", "fi", "esac"}:
        return "This keyword marks the beginning or end of the shell control construct."
    return "This line is part of the displayed section. Use nearby lines to read the enclosing statement or block."


def show_range(name, start, end):
    lines = SOURCES[name].splitlines()
    if not 1 <= start <= end <= len(lines):
        print(f"{name} has lines 1 through {len(lines)}. Choose a range inside that interval.")
        return 1
    print(f"\n{name}, lines {start}-{end}")
    section = ""
    for i in range(start, end + 1):
        label = next(label for first, label in reversed(SECTIONS[name]) if first <= i)
        if section != label:
            section = label
            print(f"\n{label}")
        line = lines[i - 1]
        print(f"{i:3}  {line}")
        print("     " + describe_line(line))
    return 0


def normalize(text):
    return " ".join(text.split())


def explain(number, query):
    query = query.strip()
    if not query:
        return 1
    lower = query.casefold()
    if lower in {"topics", "concepts", "glossary"}:
        print(f"\nTopics for Practical {number}")
        for title in TOPICS[number]:
            print(f"\n{title}\n{CONCEPTS[title]}")
        print("\nAsk by topic name, enter viva, or use a numbered source range.")
        return 0
    if lower in {"viva", "questions", "viva questions"}:
        for index, (question, answer) in enumerate(PAPER[number][-1], 1):
            print(f"\n{index}. {question}\n{answer}")
        return 0
    if lower in {"source", "code", "lines"}:
        show_source(number)
        return 0
    if lower in FILES[number]:
        show_source(number, lower)
        return 0
    if lower in {"overview", "process", "algorithm", "how does it work"}:
        print("\n" + PAPER[number][1])
        for index, step in enumerate(PAPER[number][2], 1):
            print(f"{index}. {step}")
        return 0
    if lower == "terms":
        print("\n".join(sorted(CONCEPTS, key=str.casefold)))
        return 0

    line_phrase = re.search(r"\blines?\s+(\d+)(?:\s*(?:to|through|-)\s*(\d+))?\b", lower)
    if line_phrase:
        first, last = line_phrase.groups()
        filename = next((name for name in FILES[number] if name in lower), FILES[number][0])
        return show_range(filename, int(first), int(last or first))

    range_items = query.split(",")
    ranges = [re.fullmatch(r"(?:(\w+\.\w+):)?\s*(\d{1,6})(?:\s*[-:]\s*(\d{1,6}))?", part.strip())
              for part in range_items]
    if all(ranges):
        default = FILES[number][0]
        for match in ranges:
            filename, first, last = match.groups()
            if filename:
                default = filename.casefold()
            if default not in FILES[number]:
                print("Choose a file from " + ", ".join(FILES[number]) + ".")
                return 1
            if show_range(default, int(first), int(last or first)):
                return 1
        return 0

    # Match pasted code even when its indentation differs or a terminal joins lines.
    snippet = normalize(query)
    if len(snippet) > 2:
        displayed = set()
        for name in FILES[number]:
            lines = SOURCES[name].splitlines()
            for index in range(len(lines)):
                if normalize(lines[index]) == snippet:
                    key = (name, index + 1, index + 1)
                else:
                    key = None
                if key:
                    show_range(*key)
                    displayed.add(key)
            if not displayed and snippet in normalize(SOURCES[name]):
                width = max(2, len(query.splitlines()), snippet.count(";") + 4)
                for index in range(len(lines)):
                    for end in range(index + 1, min(index + width, len(lines)) + 1):
                        if normalize("\n".join(lines[index:end])) == snippet:
                            key = (name, index + 1, end)
                            show_range(*key)
                            displayed.add(key)
                            break
                    if displayed:
                        break
        if displayed:
            print("\nThe source listing above uses the assistant's saved code.")
            return 0

    for name in FILES[number]:
        lines = SOURCES[name].splitlines()
        sections = SECTIONS[name]
        for i, (first, label) in enumerate(sections):
            declaration = lines[first - 1].strip()
            if not re.match(r"^(static |int main|bool isSafeState|update_record)", declaration):
                continue
            routine = re.search(r"(\w+)\s*\(", declaration)
            if routine and routine.group(1) != "main" and re.search(r"\b" + routine.group(1).casefold() + r"\b", lower):
                last = sections[i + 1][0] - 1 if i + 1 < len(sections) else len(lines)
                print(f"\n{routine.group(1)}() in {name}\n{label}.")
                print(f"Type {name}:{first}-{last} for the full block.")
                show_range(name, first, min(first + 4, last))
                return 0

    matches = []
    for title, aliases in ALIASES.items():
        hits = [alias for alias in aliases if re.search(r"(?<!\w)" + re.escape(alias) + r"(?!\w)", lower)]
        if hits:
            exact = any(alias == lower for alias in hits)
            matches.append((exact, max(map(len, hits)), title in TOPICS[number], title))
    matches.sort(reverse=True)
    if matches:
        if matches[0][0]:
            matches = [match for match in matches if match[0]]
        print("\n" + "\n\n".join(title + "\n" + CONCEPTS[title] for _, _, _, title in matches[:5]))
        if re.search(r"\b(difference|versus|vs)\b", lower):
            if "zombie" in lower and "orphan" in lower:
                print("\nViva comparison\nA zombie is already dead and waiting to be reaped. An orphan is alive and changes parent.")
            if "semaphore" in lower and "mutex" in lower:
                print("\nViva comparison\nA mutex protects a region with ownership. A semaphore tracks permits or signals availability between threads.")
        return 0

    print("I could not match that question in the offline lesson or source. Try a keyword from topics, "
          "a named function, a source range, or viva.")
    return 1


def self_test():
    """Compile and exercise the shipped sources through the Linux runner."""
    if sys.platform == "win32":
        windows_backend()
    if not (sys.platform == "win32" or sys.platform.startswith("linux")):
        raise RuntimeError("Self-test needs Ubuntu/Linux or Windows with WSL.")
    with tempfile.TemporaryDirectory(prefix="os-practical-test-") as test_root:
        folder = Path(test_root)

        def exercise(number, input_text="", mode="normal", expected_code=0):
            save_sources(number, folder)
            p = subprocess.run(run_command(number, mode, folder), cwd=folder,
                               input=input_text.encode("utf-8"), capture_output=True, timeout=40)
            out, err = decode_text(p.stdout), decode_text(p.stderr)
            if p.returncode != expected_code:
                raise RuntimeError(f"Practical {number} returned {p.returncode}. {err}\n{out[:1200]}")
            return out

        def require(number, condition, message):
            if not condition:
                raise RuntimeError(f"Practical {number}: {message}")

        out = exercise(1, "1\n3\nA. Patil\n12345\nPune\n2\n5\nA. Patil\nA. Patil\n45678\nPune\n"
                          "2\n4\nA. Patil\n2\n6\n")
        require(1, "A. Patil | 12345 | Pune" in out and "A. Patil | 45678 | Pune" in out
                and (folder / "addressbook.txt").read_bytes() == b"", "address book operations failed.")
        print("PASS 1: address book")

        out = exercise(2, "6\n2 9 7 5 6 1\n")
        require(2, out.count("1 2 5 6 7 9 ") == 2 and "Child process completed." in out,
                "expected both sorts and the completion message.")
        require(2, "reaped" in exercise(2, mode="zombie") and "changed PPID" in exercise(2, mode="orphan"),
                "zombie/orphan messages missing.")
        print("PASS 2: sorts, zombie and orphan")

        out = exercise(3)
        require(3, re.findall(r"^Produced:(\d+)$", out, re.M) == list("123456")
                and re.findall(r"^Consumed:(\d+)$", out, re.M) == list("123456"), "expected items 1 through 6.")
        print("PASS 3: five-slot producer-consumer")

        out = exercise(4, mode="sample", expected_code=124)
        require(4, all(f"Philosopher {i} is THINKING" in out for i in range(1, 6))
                and "finished EATING" in out, "the philosophers did not make progress during the sample.")
        print("PASS 4: dining philosophers made progress within 5 seconds")

        out = exercise(5)
        require(5, "P0 -> P1 -> P2 -> P3" in out, "the safe sequence did not match the handout.")
        print("PASS 5: Banker sample")

        out = exercise(6, "Hello world! This is a FIFO full-duplex test.\nInter-process communication in C is efficient.\nexit\n")
        require(6, all(str(count) in out for count in (45, 46))
                and "Total Words     : 8" in out and "Total Words     : 6" in out
                and out.count("Total Lines     : 1") == 2 and "Total Characters: 46" in
                (folder / "report.txt").read_text(encoding="utf-8"), "the FIFO reports did not match the handout.")
        out = exercise(6, "a sentence sent before EOF\n")
        require(6, "Process 2 terminating." in out, "the second process did not shut down on EOF.")
        print("PASS 6: both FIFOs, two reports, exit and EOF")

        contents = "OS lab pipe sample 0123456789\n" * 8000
        (folder / "test file.txt").write_bytes(contents.encode("ascii"))
        out = exercise(7, "test file.txt\n")
        require(7, contents in out, "a file larger than the pipe buffer was truncated or blocked.")
        out = exercise(7, "missing.txt\n")
        require(7, "Error: Could not open the specified file." in out, "missing-file response absent.")
        print("PASS 7: unnamed pipes, large file, spaces in path and missing file")

        out = exercise(8, "8\n25 65 43 98 57 89 102 10\n57\n199\n")
        require(8, re.findall(r"Total seek time = (\d+)", out) == ["155", "331", "170"],
                "the three seek totals did not match the handout.")
        print("PASS 8: expected seek totals 155, 331, 170")
    print("All eight practicals passed this Linux smoke test.")
    return 0


def show_practicals(heading):
    print(f"\n{heading}")
    items = [f"  [{number}] {title}" for number, title in TITLES.items()]
    half = len(items) // 2
    column_width = max(map(len, items[:half])) + 5
    total_width = column_width + max(map(len, items[half:]))
    if shutil.get_terminal_size().columns >= total_width:
        for left, right in zip(items[:half], items[half:]):
            print(left.ljust(column_width) + right)
    else:
        print("\n".join(items))


def practical_prompt(heading):
    show_practicals(heading)
    print("\n  [0] Back")
    value = read_prompt("Choose > ")
    if value is None or value.strip() == "0":
        return None
    if value.strip() not in "1 2 3 4 5 6 7 8".split():
        print("Choose a practical from 1 to 8.")
        return None
    return int(value)


def show_diagnosis():
    print("\nOffline error help")
    print("  Start with ubuntu for the college lab steps.")
    print("  Other topics: gcc, python, files, encoding, fifo, or a practical number.")
    print("  You can also paste an error or type paste for several lines.")
    error = read_prompt("Topic or error (0 = back) > ")
    if error is not None and error.strip() != "0":
        error = expanded_input(error)
        if error.strip():
            print()
            for tip in diagnose(error):
                print("  " + tip)


def handle_run(number, cwd, action, mode="normal", here=False, compact=False):
    folder = save_sources(number, cwd)
    names = ", ".join(FILES[number])
    if compact:
        print(f"\n  Saved {names}")
        if folder != cwd:
            print(f"  Folder  {folder}")
        sys.stdout.flush()
    else:
        print(f"Saved {names} in {folder}", flush=True)
    if action == "save":
        return 0
    if action == "check":
        return run_program(number, "check", folder)
    if here:
        return run_program(number, mode, folder)
    return start_in_terminal(number, mode, folder)


def run_menu(cwd):
    while True:
        show_practicals("Run a practical")
        print("\n  [0] Back   [D] Error help   [T] Test all")
        print("  [2Z] Zombie demo   [2O] Orphan demo")
        option = read_prompt("Choose > ")
        if option is None:
            return
        choice = option.strip().casefold()
        if choice == "0":
            return
        if choice == "d":
            show_diagnosis()
            continue
        if choice not in {"1", "2", "3", "4", "5", "6", "7", "8", "2z", "2o", "t"}:
            print("Choose a practical from 1 to 8.")
            continue
        try:
            if choice == "t":
                self_test()
                continue
            mode = {"2z": "zombie", "2o": "orphan"}.get(choice, "normal")
            handle_run(int(choice[0]), cwd, "run", mode, compact=True)
        except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
            report_exception(exc)
        except KeyboardInterrupt:
            print("\nStopped.")
        return


def study_menu(number):
    names = ", ".join(FILES[number])
    example = "process2.c:25-40" if number == 6 else "15-25 or 10,15-18"
    print(f"\nPractical {number} | {TITLES[number]}\nSource: {names}")
    print("Type topics, overview, viva, source, or a question such as what is a semaphore?")
    print(f"For lines, type {example}. For pasted text, type paste, clip, or file <path>.")
    while True:
        question = read_prompt("Explain (0 = back): ")
        if question is None or question.strip() == "0":
            return
        explain(number, expanded_input(question))


def run_menu_screen(cwd):
    print("\nOS PRACTICALS ASSISTANT")
    print(f"Folder  {cwd}")
    while True:
        print("\n  [1] Run a practical")
        print("  [2] Paper write-up")
        print("  [3] Code explainer and viva")
        print("  [0] Exit")
        option = read_prompt("Choose > ")
        if option is None or option.strip() == "0":
            return 0
        choice = option.strip()
        if choice == "1":
            run_menu(cwd)
        elif choice in {"2", "3"}:
            heading = "Paper write-up" if choice == "2" else "Code explainer and viva"
            number = practical_prompt(heading)
            if number is not None:
                if choice == "2":
                    show_paper(number)
                else:
                    study_menu(number)
        else:
            print("Choose 1, 2, 3, or 0.")


def main():
    configure_console()
    if len(sys.argv) == 1 and desktop_launch():
        if open_terminal(["--desktop-menu"], working_folder(Path(__file__).resolve().parent)):
            return 0
        if sys.stderr is not None:
            print("A desktop terminal could not be opened.", file=sys.stderr)
        return 1
    parser = argparse.ArgumentParser(description=__doc__,
                                     epilog="Without arguments, an offline menu opens in the current directory.")
    action = parser.add_mutually_exclusive_group()
    for name, description in (
        ("run", "save and launch this practical"),
        ("save", "save embedded source only"),
        ("check", "save and check dependencies and compilation"),
        ("paper", "print the paper write-up"),
        ("source", "print line-numbered code"),
        ("explain", "answer a question or explain code lines"),
    ):
        action.add_argument("--" + name, type=int, choices=range(1, 9), metavar="N", help=description)
    action.add_argument("--self-test", action="store_true", help="compile and test all eight in Linux")
    parser.add_argument("--query", help="question, concept, topic or line range for --explain")
    parser.add_argument("--mode", choices=("normal", "zombie", "orphan"), default="normal",
                        help="optional run mode for Practical 2")
    parser.add_argument("--here", action="store_true", help="run in this terminal without opening another")
    parser.add_argument("--child", action="store_true", help=argparse.SUPPRESS)
    action.add_argument("--desktop-menu", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.mode != "normal" and args.run != 2:
        parser.error("--mode zombie/orphan requires --run 2.")
    if args.explain and not args.query:
        parser.error("--explain needs --query, for example --explain 3 --query \"What is a semaphore?\"")

    try:
        if args.paper:
            show_paper(args.paper)
            return 0
        if args.source:
            show_source(args.source)
            return 0
        if args.explain:
            return explain(args.explain, expanded_input(args.query))
        if args.self_test:
            return self_test()
        cwd = working_folder(Path.cwd())
        if args.run:
            return handle_run(args.run, cwd, "run", args.mode, args.here or args.child)
        if args.save:
            return handle_run(args.save, cwd, "save")
        if args.check:
            return handle_run(args.check, cwd, "check")
        return run_menu_screen(cwd)
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        report_exception(exc)
        return 1
    except KeyboardInterrupt:
        print("\nStopped.")
        return 130
    finally:
        if args.child and sys.stdin.isatty():
            try:
                read_prompt("\nPress Enter to close this terminal.")
            except KeyboardInterrupt:
                pass


if __name__ == "__main__":
    sys.exit(main())
