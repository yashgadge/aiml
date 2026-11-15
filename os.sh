#!/usr/bin/env bash
if LC_ALL=C grep -Uq $'\r$' -- "$0"; then sed -b -i --follow-symlinks $'s/\r$//' -- "$0" || { printf '%s\n' 'Could not repair the line endings. Copy the launcher into a writable folder under Home and open it there.' >&2; exit 1; }; printf 'Fixed Windows line endings in %s.\n' "${0##*/}"; exec "$BASH" "$0" "$@"; fi; : ''

if (( BASH_VERSINFO[0] < 4 )); then
    printf '%s\n' 'This assistant needs Bash 4 or newer.' >&2
    exit 1
fi

titles=(
    '' 'Address book (Bash)' 'Processes and sorting' 'Producer-consumer'
    'Dining philosophers' "Banker's algorithm" 'Named pipes (FIFO)' 'Unnamed pipes'
    'Disk scheduling'
)

practical_sources() {
    case $1 in
        1) printf '%s\n' practical1.sh ;;
        6) printf '%s\n' process1.c process2.c ;;
        *) printf 'practical%s.c\n' "$1" ;;
    esac
}


sources=(practical1.sh practical2.c practical3.c practical4.c practical5.c
         process1.c process2.c practical7.c practical8.c)

write_source() {
    case $1 in
        practical1.sh)
            cat <<'END_practical1_sh'
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
END_practical1_sh
            ;;
        practical2.c)
            cat <<'END_practical2_c'
#define _POSIX_C_SOURCE 200809L
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
END_practical2_c
            ;;
        practical3.c)
            cat <<'END_practical3_c'
#define _POSIX_C_SOURCE 200809L
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
END_practical3_c
            ;;
        practical4.c)
            cat <<'END_practical4_c'
#define _POSIX_C_SOURCE 200809L
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
END_practical4_c
            ;;
        practical5.c)
            cat <<'END_practical5_c'
#include <stdio.h>
#include <stdbool.h>

#define P 4
#define R 3

bool isSafeState(int available[R], int max[P][R], int allocation[P][R], int safeSequence[P]) {
    int need[P][R];
    int work[R];
    bool finish[P] = {false};

    for (int i = 0; i < P; i++) {
        for (int j = 0; j < R; j++) {
            need[i][j] = max[i][j] - allocation[i][j];
        }
    }

    for (int i = 0; i < R; i++) {
        work[i] = available[i];
    }

    int count = 0;
    while (count < P) {
        bool foundProcess = false;

        for (int p = 0; p < P; p++) {
            if (!finish[p]) {
                bool canAllocate = true;

                for (int j = 0; j < R; j++) {
                    if (need[p][j] > work[j]) {
                        canAllocate = false;
                        break;
                    }
                }
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

        if (!foundProcess) {
            return false;
        }
    }

    return true;
}

int main(void) {
    int available[R] = {1, 1, 1};

    int max[P][R] = {
        {2, 2, 1},
        {2, 1, 2},
        {3, 2, 2},
        {1, 2, 1}
    };

    int allocation[P][R] = {
        {1, 1, 0},
        {1, 0, 1},
        {1, 1, 1},
        {0, 1, 0},
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
END_practical5_c
            ;;
        process1.c)
            cat <<'END_process1_c'
#define _POSIX_C_SOURCE 200809L
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
END_process1_c
            ;;
        process2.c)
            cat <<'END_process2_c'
#define _POSIX_C_SOURCE 200809L
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
END_process2_c
            ;;
        practical7.c)
            cat <<'END_practical7_c'
#define _POSIX_C_SOURCE 200809L
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
    int pipe1[2];
    int pipe2[2];
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
END_practical7_c
            ;;
        practical8.c)
            cat <<'END_practical8_c'
#include <limits.h>
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
END_practical8_c
            ;;
        *) return 1 ;;
    esac
}

run_native() (
    number=$1
    mode=$2
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
)


write_walkthrough() {
    case $1 in
        1)
            cat <<'END_WRITE_WALKTHROUGH_1'
What goes in and what comes out
  Input: a menu number and, for record operations, a name, phone number and city.
  Storage: addressbook.txt in the working directory. Each line is a record.
  Output: the current records or a message about the requested operation.
  A phone number is text. Storing it as a number could drop leading zeros.

Code blocks and data flow
  while true repeats the menu. read gets the choice; case sends it to the
  correct branch. 6 exits. End of input also leaves the menu loop.
  > opens an empty file for Create. >> appends a record without erasing the
  earlier records. printf uses a fixed format and inserts the three fields.
  In update_record(), mktemp creates a temporary file. AWK copies the lines
  whose prefix is different from the literal name plus " | ". ENVIRON passes
  the name as data, so a dot in a name does not act as a regular expression.
  Delete moves the filtered file over the old one. Modify adds the new line
  first, then replaces the original. If no name matches, neither changes it.

Dry run
  1                 Create an empty addressbook.txt.
  3, Asha Patil     Read the name, then 9876543210, then Pune.
  2                 Print: Asha Patil | 9876543210 | Pune
  5, Asha Patil     Enter the replacement name, phone and city when asked.
  2                 Verify that the new record is present.
  4, Asha Patil     Delete that name, assuming it was kept during Modify.
  2                 The Address Book heading remains, with no record below it.
  6                 Exit. Reopening the program preserves the file.

Checks and limits
  Try an absent name and a name containing a dot. Matching is case-sensitive.
  When several records have exactly the same name, Delete removes all matches.
  Modify removes those matches and appends one replacement at the end.
  View, Delete and Modify may scan the whole file, so their time is O(n) for n
  records. The temporary copy can take O(n) additional space. Create clears
  the file; avoid choosing it if you want to retain your records.
  If the file cannot be saved, run from a writable folder under Home.
END_WRITE_WALKTHROUGH_1
            ;;
        2)
            cat <<'END_WRITE_WALKTHROUGH_2'
What goes in and what comes out
  Input: a positive count n and n integers, including duplicates or negatives.
  Output: the child's Selection Sort result, the parent's Bubble Sort result,
  and a completion message. The displayed process IDs are assigned at runtime.
  The separate zombie and orphan modes take no sorting input.

Code blocks and data flow
  main() reads the array and flushes buffered output before fork().
  The child's fork() result is 0. It sorts its own copy with Selection Sort.
  The parent's result is the child's PID. The parent sorts with Bubble Sort
  and uses waitpid() to collect the child before printing its own list.
  Linux can initially share memory pages using copy-on-write. A modification
  belongs to the writer's process, which is why neither sort alters the other.
  wait_for_child() retries if waitpid() is interrupted and checks the exit
  status. A valid collected exit is different from a failed fork.

Dry run with 2 9 7 5 6 1
  Bubble pass 1: 2 7 5 6 1 9   (largest remaining value reaches the end)
  Bubble pass 2: 2 5 6 1 7 9
  Bubble pass 3: 2 5 1 6 7 9
  Bubble passes 4 and 5: 2 1 5 6 7 9 -> 1 2 5 6 7 9
  Selection pass 1: 1 9 7 5 6 2   (select the minimum, then swap)
  Selection pass 2: 1 2 7 5 6 9
  Selection pass 3: 1 2 5 7 6 9
  Selection passes 4 and 5: 1 2 5 6 7 9
  Expected lines:
    Sorted by Child (Selection Sort): 1 2 5 6 7 9
    Sorted by Parent (Bubble Sort): 1 2 5 6 7 9
    Child process completed.

Process state demonstrations
  2Z Zombie: the child exits. waitid() with WNOWAIT reports its exit without
  collecting it. A later waitpid() reaps the zombie and removes the entry.
  2O Orphan: an intermediate process creates a grandchild and exits. The still
  running grandchild reports that its PPID changed. Its own PID stays the same.
  A zombie has already stopped; an orphan is alive at the time of reparenting.

Checks and limits
  Try n = 1 or repeated values. Both sorts do O(n^2) comparisons in this
  implementation and use O(1) extra sorting storage. The input array takes
  O(n) memory. Enter exactly n whole numbers; Ctrl+D ends input on Ubuntu.
END_WRITE_WALKTHROUGH_2
            ;;
        3)
            cat <<'END_WRITE_WALKTHROUGH_3'
What goes in and what comes out
  There is no keyboard input. One producer sends the integers 1 through 6
  through a five-slot buffer. One consumer takes them in the same order.
  Output includes one Produced and one Consumed line for each integer.

Code blocks and shared state
  buffer[5] holds the items. empty starts at 5 and counts available slots;
  full starts at 0 and counts items ready to consume. A mutex protects the
  small section where a thread accesses the array and prints its operation.
  Producer: wait(empty) -> lock -> store -> unlock -> post(full).
  Consumer: wait(full)  -> lock -> read  -> unlock -> post(empty).
  The producer and consumer have their own loop counters. Each uses index
  i % BUFFER_SIZE so the sixth item uses slot 0 again. The semaphore order
  ensures that the producer can reuse it only after space becomes available.
  main() creates both threads, joins both and then destroys the resources.

One possible dry run
  Event                        empty  full   Meaning
  Initial state                    5     0   Consumer would wait.
  Producer completes item 1         4     1   Item 1 is ready in slot 0.
  Consumer completes item 1         5     0   Slot 0 can be reused later.
  Continue for items 2 through 5. Item 6 is stored and read at index 5 % 5 = 0.
  The table shows counts after completed operations. In the middle of an
  operation, a taken permit may not yet have been posted to the opposite count.

Reading the output
  You should see Produced:1 through Produced:6 and Consumed:1 through
  Consumed:6 in order within each thread. The two sets of lines may interleave
  differently on another run. A consumer cannot take an item before it exists.

Checks and limits
  Full and empty semaphores prevent overflow and underflow. The mutex protects
  shared access but does not enforce capacity. Wait for the permit before
  acquiring the mutex so a blocked worker does not trap the other worker.
  Each operation does O(1) work apart from waiting. Buffer storage is O(B)
  for capacity B. If thread symbols fail to link, keep the -pthread flag.
END_WRITE_WALKTHROUGH_3
            ;;
        4)
            cat <<'END_WRITE_WALKTHROUGH_4'
What goes in and what comes out
  No keyboard input. Five threads repeatedly think, pick forks, eat and put
  forks down. Their messages appear in whatever order the OS schedules them.
  Use Ctrl+C to stop after observing several rounds.

Code blocks and resource layout
  forks[5] holds one semaphore per fork, each initialized to 1. room starts
  at 4 and counts how many philosophers may compete for forks.
  For zero-based philosopher i, left = i and right = (i + 1) % 5. Printed
  IDs add 1. Thus philosopher 5 uses printed forks 5 and 1.
  Each thread thinks, waits for room, takes its two forks, eats, releases
  both forks, leaves the room and repeats. main() keeps each ID in its own
  array entry so threads do not share a changing loop counter.

One possible dry run
  Philosopher 1 is THINKING
  Philosopher 1 picked LEFT fork 1
  Philosopher 1 picked RIGHT fork 2
  Philosopher 1 is EATING
  Philosopher 1 finished EATING
  A neighbor needs one of forks 1 or 2 and cannot eat simultaneously.
  Philosopher 3 could eat with forks 3 and 4 while philosopher 1 eats.

Why the limit matters
  With five room permits, each philosopher could hold its left fork and wait
  for the right fork held by the next person. No one could finish and release
  a fork. With four permits, at least one philosopher cannot take a left fork;
  when the four contenders hold their left forks, one can acquire the free fork
  and make progress. The limit prevents this circular deadlock, but the
  semaphores do not guarantee that every philosopher gets equal turns.

Checks and limits
  A pause between messages is expected because the threads sleep before and
  after eating. Observe that philosopher 5's right fork wraps to 1 and that
  each eater logs both acquisitions first. The program has no fixed final
  meal count. If it fails to link, compile with -pthread.
END_WRITE_WALKTHROUGH_4
            ;;
        5)
            cat <<'END_WRITE_WALKTHROUGH_5'
What goes in and what comes out
  No keyboard input. The code uses four processes and three resource types
  (A, B, C). Max and Allocation are matrices; Available is a vector.
  Need[i][j] = Max[i][j] - Allocation[i][j]. Work is the simulated pool of
  free resources. Finish marks processes that the simulation can complete.

Data used by the program
  Process    Allocation    Max        Need
  P0         (1,1,0)       (2,2,1)    (1,1,1)
  P1         (1,0,1)       (2,1,2)    (1,1,1)
  P2         (1,1,1)       (3,2,2)    (2,1,1)
  P3         (0,1,0)       (1,2,1)    (1,1,1)
  Available = (1,1,1). Compare every component of Need to Work. Equal
  values are allowed because exactly enough resources can satisfy a claim.

Dry run of the safety check
  Step   Work before   Process chosen   Work after
  1      (1,1,1)       P0               (2,2,1)
  2      (2,2,1)       P1               (3,2,2)
  3      (3,2,2)       P2               (4,3,3)
  4      (4,3,3)       P3               (4,4,3)
  In each row Work grows by the selected process's original Allocation.
  Its remaining Need can be borrowed from Work and returned on completion,
  so the net increase is its original Allocation.

Reading the output
  Result: The system is in a SAFE state.
  Safe Execution Sequence: P0 -> P1 -> P2 -> P3
  Another valid safe sequence may exist; the code finds one by scanning from
  the first row. On paper, try initial Work = (0,0,0) with the same rows. No
  row can first complete, so this hypothetical state fails the safety test.

Checks and limits
  isSafeState() checks safety for the supplied snapshot. A full request
  handler would make a tentative allocation, recheck safety, and roll back
  if unsafe. There are at most n successful passes for n processes, each
  scanning up to n rows with m resources, so worst-case time is O(n^2 m).
  The Need matrix uses O(nm) storage; Work and Finish add O(m+n).
END_WRITE_WALKTHROUGH_5
            ;;
        6)
            cat <<'END_WRITE_WALKTHROUGH_6'
What goes in and what comes out
  Process 1 reads one line from the terminal. Process 2 counts bytes, words
  and lines, writes the latest report to report.txt and returns it for display.
  A named pipe (FIFO) has a filesystem path. Data moves through a kernel
  stream; the pathname lets two separately launched processes find it.

Two directions and the order of events
  Terminal -> Process 1 --fifo1--> Process 2
  Terminal <- Process 1 <--fifo2-- Process 2
  1. Launcher creates both FIFOs and starts the two programs.
  2. Process 1 reads a sentence, removes the line ending and sends the line
     to fifo1. Closing its writer finishes the request for that iteration.
  3. Process 2 reads the request. It stops on the exact string exit.
  4. Otherwise it scans the bytes. Whitespace ends a word; transition from
     whitespace to non-whitespace starts a new word. Punctuation such as
     the comma in "Hello," remains part of the word.
  5. Process 2 writes report.txt, rewinds the file, copies it through fifo2
     and closes it. Process 1 reads the reply and prints it to the terminal.
  6. Repeat for the next sentence. Typing exit ends both programs.

Dry run
  Input: Hello world!
  The two words have 5 and 6 bytes, plus one space, so the total is 12.
  The Enter key adds a line ending, which the program removes. The report is:
    Original Text: Hello world!
    Total Characters: 12
    Total Words     : 2
    Total Lines     : 1
  Another sample, Hello world! This is a FIFO full-duplex test., gives
  45 bytes, 8 words and 1 line. An empty input line gives 0, 0 and 0.

Checks and limits
  A named pipe opened for reading or writing may wait for the other side.
  Start both programs in the same directory for a manual run. A regular file
  with the same name is not a FIFO. The launcher creates its own pipes.
  The latest report replaces the prior one. UTF-8 characters may use more than
  one byte; the reported character count is a byte count. The analysis takes
  O(L) time for L input bytes. The dynamic input buffer grows with the line.
END_WRITE_WALKTHROUGH_6
            ;;
        7)
            cat <<'END_WRITE_WALKTHROUGH_7'
What goes in and what comes out
  Enter a pathname, such as sample.txt or an absolute path. The child reads
  the file and the parent displays its bytes. The program does not need to
  know in advance how long the file is. The lab sample uses a readable text
  file because its bytes can be shown directly in a terminal.

Two inherited pipes
  pipe1 takes the pathname from parent to child.
  pipe2 takes the contents or an error message from child to parent.
  For both arrays, index 0 is read and index 1 is write.
  Process     Keep                   Close immediately
  Parent      pipe1[1], pipe2[0]     pipe1[0], pipe2[1]
  Child       pipe1[0], pipe2[1]     pipe1[1], pipe2[0]

Code blocks and ordering
  pipe() is called before fork() so both processes inherit the descriptors.
  Parent uses getline(), strips the line ending and sends the pathname with
  the terminating NUL. Child uses getdelim() with NUL to read that message.
  Child calls open() in read-only mode. Each read() may return fewer bytes
  than the buffer holds. write_all() repeats until the entire chunk is sent.
  Parent drains pipe2 to EOF before calling waitpid(). If it waited first,
  a large file could fill the pipe and block the child that it is waiting for.
  EOF arrives only when the parent has drained the data and every copy of
  the write descriptor has been closed.

Dry run and checks
  Make a text file called sample.txt containing one line, Hello from a pipe.
  Enter sample.txt. The terminal prints the content under
  "--- Content received from Child Process ---".
  Try a missing file: the child sends "Error: Could not open the specified file."
  A relative path starts from the folder where the run terminal opened.
  Use the actual filename and capitalization. If a path contains spaces, type
  the full path at the program prompt without adding shell quotes.
  Try an empty file and one much larger than a pipe buffer. An empty file
  has no content between the headings. Large files are read in chunks.
  Time is O(F) for F file bytes; the transfer buffers have constant size.
END_WRITE_WALKTHROUGH_7
            ;;
        8)
            cat <<'END_WRITE_WALKTHROUGH_8'
What goes in and what comes out
  Input: 1 to 100 requests, the request queue, the head position and the
  maximum valid cylinder. The head and each request must be in range.
  Output: each algorithm's service path and total cylinder movement.
  Starting position and a request at that same position can both appear,
  with zero additional movement.

How the algorithms choose the next position
  SSTF repeatedly scans unserved requests for minimum absolute distance.
  The done array marks served entries. If two are equally close, the first
  unserved entry in the original order wins.
  SCAN sorts the requests, serves the high side first, continues to the
  maximum cylinder, then reverses to serve the low side in descending order.
  C-LOOK sorts the requests, serves the high side, jumps to the lowest
  remaining request and continues upward. It has no mandatory endpoint.
  The program counts that jump in total movement. It uses a wide integer
  for distance totals and allows duplicate cylinder requests.

Worked dry run
  Requests: 25 65 43 98 57 89 102 10  |  Head: 57  |  Max: 199
  SSTF:   57 -> 57 -> 65 -> 43 -> 25 -> 10 -> 89 -> 98 -> 102
          0 + 8 + 22 + 18 + 15 + 79 + 9 + 4 = 155
  SCAN:   57 -> 57 -> 65 -> 89 -> 98 -> 102 -> 199 -> 43 -> 25 -> 10
          0 + 8 + 24 + 9 + 4 + 97 + 156 + 18 + 15 = 331
  C-LOOK: 57 -> 57 -> 65 -> 89 -> 98 -> 102 -> 10 -> 25 -> 43
          0 + 8 + 24 + 9 + 4 + 92 + 15 + 18 = 170

Checks and limits
  Try requests on only one side of the head, duplicate requests, and a
  request at the head. Type the highest valid cylinder, not the number of
  cylinders; cylinders 0 through 199 mean a maximum of 199.
  SSTF uses O(n^2) comparisons. SCAN and C-LOOK each take O(n) traversal
  after the shared sort; sorting time depends on the qsort implementation.
  The demo assumes a rotating-disk head model. Its label "Total seek time"
  is a distance total in cylinders. Physical timing also depends on hardware.
END_WRITE_WALKTHROUGH_8
            ;;
        *) return 1 ;;
    esac
}

write_paper() {
    case $1 in
        1)
            cat <<'END_WRITE_PAPER_1'
PRACTICAL 1  Address book (Bash)

Title and aim
Implement an address book using a Bash script with create, view, insert, delete, modify, and exit operations.

Requirements
Ubuntu, Bash, and a writable folder.

Theory
A Bash script groups terminal commands into a program. A loop repeats the menu and case selects an operation. The address book is a local text file, with one Name | Phone | City record per line. A temporary file makes updates safer.

Algorithm
1. Set addressbook.txt as the data file. Repeat the menu until Exit or end of input.
2. For Create, open the file with > to make an empty book. For View, check that it exists and display it using cat.
3. For Insert, read the name, phone and city, then append one formatted record using >>.
4. For Delete, copy every record except the matching literal name into a temporary file.
5. For Modify, filter the old name, read the replacement, and append it to the temporary file.
6. Move the temporary file over the book only after the update succeeds.

Manual procedure
bash practical1.sh

Program
Write the source with the filename(s) practical1.sh.

Sample input or observation steps
Choose 1, then 3. Enter Asha Patil, 9876543210, and Pune on separate lines. Then choose 2.

Expected output and result
The view displays Asha Patil | 9876543210 | Pune. Choose 6 to exit.

Conclusion
Bash control flow and text-file redirection implement a persistent address book.
END_WRITE_PAPER_1
            ;;
        2)
            cat <<'END_WRITE_PAPER_2'
PRACTICAL 2  Processes and sorting

Title and aim
Demonstrate fork() and waitpid() with parent and child sorting, and show zombie and orphan states in separate modes.

Requirements
Ubuntu, GCC, Bash, a terminal, and a writable folder.

Theory
fork creates a child process with its own virtual address space. The parent and child initially see the same input values. Each sorts its own copy. A zombie has already exited but has not been collected. An orphan is alive after its original parent exits.

Algorithm
1. Read the integer count and the integers. Flush pending output before forking.
2. Call fork. A negative return indicates failure. Zero takes the child branch; a positive PID takes the parent branch.
3. The child sorts with Selection Sort, repeatedly choosing the smallest remaining value.
4. The parent sorts with Bubble Sort, swapping adjacent values that are out of order.
5. Collect the child using waitpid and display both sorted results and the completion message.
6. In zombie mode, use waitid with WNOWAIT to observe the exited child, then reap it. In orphan mode, compare the live child's old and new parent PIDs.

Manual procedure
gcc practical2.c -o practical2 && ./practical2

Program
Write the source with the filename(s) practical2.c.

Sample input or observation steps
Enter 6, then 2 9 7 5 6 1. Run the optional zombie and orphan modes separately.

Expected output and result
Both processes print 1 2 5 6 7 9. Process IDs vary. The separate modes show a reaped child and reparenting.

Conclusion
The program demonstrates process creation, independent address spaces, lifecycle states, and synchronization through a wait.
END_WRITE_PAPER_2
            ;;
        3)
            cat <<'END_WRITE_PAPER_3'
PRACTICAL 3  Producer-consumer

Title and aim
Solve the bounded-buffer producer-consumer problem using two counting semaphores and a mutex.

Requirements
Ubuntu, GCC, Bash, a terminal, and a writable folder.

Theory
The five-slot circular buffer is shared by two threads. empty counts free slots and full counts available items. The mutex serializes the short critical section that accesses the buffer.

Algorithm
1. Initialize empty to 5, full to 0, and initialize the mutex. Create the producer and consumer.
2. Producer waits on empty, locks the mutex, writes the next item at i modulo 5, and prints it.
3. Producer unlocks the mutex and posts full to advertise the new item.
4. Consumer waits on full, locks the mutex, reads the next item at its own index modulo 5, and prints it.
5. Consumer unlocks and posts empty. Repeat until both threads handle all six items.
6. Join both threads, then destroy the synchronization objects.

Manual procedure
gcc practical3.c -pthread -o practical3 && ./practical3

Program
Write the source with the filename(s) practical3.c.

Sample input or observation steps
No input. Run the program once.

Expected output and result
Produced:1 through Produced:6 and Consumed:1 through Consumed:6. The two groups of lines can interleave.

Conclusion
Counting semaphores enforce buffer limits and a mutex protects the shared data. Circular indexing safely reuses slots.
END_WRITE_PAPER_3
            ;;
        4)
            cat <<'END_WRITE_PAPER_4'
PRACTICAL 4  Dining philosophers

Title and aim
Demonstrate synchronization for five dining philosophers and prevent circular wait using a room semaphore.

Requirements
Ubuntu, GCC, Bash, a terminal, and a writable folder.

Theory
Every philosopher is a thread. A fork is represented by a semaphore initialized to one. Each philosopher needs two adjacent forks. A room semaphore initialized to four prevents all five from holding one fork and waiting for another together.

Algorithm
1. Initialize five fork semaphores to one and the room semaphore to four. Create five threads, with IDs displayed as 1 through 5.
2. A philosopher thinks, then enters the room by waiting on room.
3. Acquire the left fork, then the right fork at the next index modulo five.
4. Eat after acquiring both forks. Release both forks and the room permit.
5. Repeat. Use Ctrl+C to end the demonstration.

Manual procedure
gcc practical4.c -pthread -o practical4 && ./practical4

Program
Write the source with the filename(s) practical4.c.

Sample input or observation steps
No input. Let it run until you see THINKING, picked LEFT/RIGHT fork, EATING and finished EATING.

Expected output and result
Philosophers continue making progress and adjacent philosophers cannot use the same fork at the same time. The exact order varies.

Conclusion
The room limit prevents circular wait in this arrangement. It does not promise that every waiting thread is scheduled fairly.
END_WRITE_PAPER_4
            ;;
        5)
            cat <<'END_WRITE_PAPER_5'
PRACTICAL 5  Banker's algorithm

Title and aim
Use the Banker's safety algorithm to determine whether the current resource allocation is safe and find a safe sequence.

Requirements
Ubuntu, GCC, Bash, a terminal, and a writable folder.

Theory
Available gives unused resources, Allocation gives assigned resources, and Max records each process's greatest possible demand. Need is Max minus Allocation. A safe state has at least one order in which everyone can finish.

Algorithm
1. Read the fixed Available, Max, and Allocation values from the program. Compute Need for every process and resource type.
2. Set Work to Available and every Finish flag to false.
3. Find an unfinished process whose Need is at most Work for every resource type.
4. Simulate its completion. Add its current Allocation to Work, mark it finished, and append it to the safe sequence.
5. Repeat until all processes finish. If a full pass finds no eligible process, report unsafe.

Manual procedure
gcc practical5.c -o practical5 && ./practical5

Program
Write the source with the filename(s) practical5.c.

Sample input or observation steps
No keyboard input. The code uses four processes, three resource types, and Available = (1, 1, 1).

Expected output and result
The sample is SAFE. Safe Execution Sequence: P0 -> P1 -> P2 -> P3.

Conclusion
The safety check decides whether the operating system can guarantee completion for the declared maximum claims.
END_WRITE_PAPER_5
            ;;
        6)
            cat <<'END_WRITE_PAPER_6'
PRACTICAL 6  Named pipes (FIFO)

Title and aim
Communicate between two independent processes using two named pipes and return a character, word, and line report.

Requirements
Ubuntu, GCC, Bash, a terminal, and a writable folder.

Theory
A FIFO is a named filesystem entry for a kernel byte stream. The first pipe sends a sentence from Process 1 to Process 2. The second sends the report back. report.txt keeps the latest completed analysis.

Algorithm
1. Create fifo1 and fifo2. Start Process 2 and Process 1. The assistant arranges this automatically.
2. Process 1 reads a sentence and strips its line ending while keeping spaces and punctuation.
3. Process 1 writes the sentence to fifo1. Process 2 reads it and checks whether it is the exit message.
4. Count bytes, whitespace-delimited words and lines. Write the report to report.txt.
5. Process 2 sends the report through fifo2. Process 1 reads and displays it.
6. Repeat until exit or terminal EOF. Both programs terminate and the assistant cleans up its private FIFOs.

Manual procedure
Terminal 1: gcc process1.c -o process1 && gcc process2.c -o process2 && mkfifo fifo1 fifo2 && ./process2
Terminal 2, in the same folder: ./process1
Create the FIFOs once. If they already exist as FIFOs, start ./process2 directly after compiling.

Program
Write the source with the filename(s) process1.c, process2.c.

Sample input or observation steps
Enter Hello world! This is a FIFO full-duplex test. Then enter exit.

Expected output and result
The report shows the text, 45 characters, 8 words, and 1 line. This example uses ASCII; non-ASCII characters may occupy multiple bytes.

Conclusion
Two one-directional FIFO channels allow a request and response between separate processes.
END_WRITE_PAPER_6
            ;;
        7)
            cat <<'END_WRITE_PAPER_7'
PRACTICAL 7  Unnamed pipes

Title and aim
Use two unnamed pipes to send a file pathname from a parent to its child and return the file contents.

Requirements
Ubuntu, GCC, Bash, a terminal, and a writable folder.

Theory
pipe creates a read and write descriptor. fork lets the child inherit both pipes. Pipes have finite capacity and provide a byte stream. Closing unused descriptors allows end of stream to be seen.

Algorithm
1. Create two pipes and fork the child.
2. Close each unused pipe end in each branch.
3. The parent reads the pathname and sends it with a terminating NUL byte on the first pipe, then closes its writer.
4. The child reads the pathname, opens the file, and copies bytes through the second pipe. If the file cannot be opened, it returns a message.
5. The parent drains the second pipe and displays the bytes. It calls waitpid after draining.
6. Close remaining descriptors and terminate.

Manual procedure
gcc practical7.c -o practical7 && ./practical7

Program
Write the source with the filename(s) practical7.c.

Sample input or observation steps
Create test.txt with printf 'Hello from a pipe.\n' > test.txt and enter test.txt at the program prompt.

Expected output and result
The parent displays Hello from a pipe. between the output headers. Relative paths are interpreted from the current working folder.

Conclusion
The two inherited pipes carry a request and its data between related processes. Draining the reply before waiting prevents a large-file block.
END_WRITE_PAPER_7
            ;;
        8)
            cat <<'END_WRITE_PAPER_8'
PRACTICAL 8  Disk scheduling

Title and aim
Compare disk scheduling using SSTF, SCAN, and C-LOOK and calculate total head movement.

Requirements
Ubuntu, GCC, Bash, a terminal, and a writable folder.

Theory
Requests are cylinder numbers. Seek distance in this exercise is the absolute difference between consecutive positions. SSTF selects the closest request. SCAN goes toward the high end then reverses. C-LOOK wraps from the last high request to the lowest pending request.

Algorithm
1. Read the number of requests, the queue, the starting head position, and the maximum cylinder. Validate the range.
2. SSTF repeatedly selects the nearest unserved request, keeping input order for ties.
3. Sort the queue by cylinder for the other algorithms.
4. SCAN services requests at and above the head, reaches the maximum cylinder, then services lower requests in descending order.
5. C-LOOK services requests at and above the head, then wraps to the lowest pending cylinder and resumes ascending order.
6. Add the absolute movement for each printed transition. In this handout the C-LOOK wrap distance is counted.

Manual procedure
gcc practical8.c -o practical8 && ./practical8

Program
Write the source with the filename(s) practical8.c.

Sample input or observation steps
Enter 8. Queue: 25 65 43 98 57 89 102 10. Head: 57. Maximum cylinder: 199.

Expected output and result
Total seek distance: SSTF = 155, SCAN = 331, C-LOOK = 170. The program prints each full service path.

Conclusion
Different scheduling strategies change both order and movement. SSTF saves movement on this sample, but selection behavior depends on workload.
END_WRITE_PAPER_8
            ;;
        *) return 1 ;;
    esac
    printf '\nDetailed walkthrough\n'
    write_walkthrough "$1"
    printf '\nViva practice\n'
    write_viva "$1"
}


write_topics() {
    case $1 in
        1)
            cat <<'END_WRITE_TOPICS_1'
Topics for Practical 1

Bash script
A text file containing shell commands. The first line #!/usr/bin/env bash tells Linux how to execute it when launched directly. bash practical1.sh explicitly starts Bash and only needs source read permission.

Working directory
Every process has a current directory. Relative filenames such as test.txt start there. Absolute Linux paths start at /. Type pwd to check your folder, ls to list it, and cd to move. Quote a path that contains spaces.

Redirection
A shell can direct output into a file. > creates or truncates; >> appends. Standard input is stream 0, normal output is stream 1, and error output is stream 2. A C program often accesses these through stdin, stdout and stderr.

Shell quotes
Double quotes allow expansion of values such as $file while keeping the resulting text together. Single quotes normally preserve characters literally. Quoting is important for spaces in filenames and user-entered text.

Shell read
Read a line into a shell variable. -r keeps backslashes literal; setting IFS= immediately before read preserves leading and trailing spaces. A failed read often means end of input.

Shell case and loop
case selects the first matching pattern. ;; ends that branch and esac closes the case. while true repeats the menu until break, exit, or a read that fails.

AWK and literal matching
AWK reads one record at a time, normally a line. index(text, target) returns a one-based starting position or 0. In the address book matching index == 1 on the name plus delimiter finds an exact literal name at the start; characters like . have no regex meaning.

Temporary file
mktemp safely creates a fresh name. The address book builds the update in that file, then mv replaces the old file once the new contents are ready. Creating it in the same directory keeps the rename on the same filesystem.

File permissions
Read permission lets the program open source, write permission on a directory lets it create entries, and execute permission lets Linux run a binary. A noexec mount can block execution even with execute bits set. bash file.sh reads a script through Bash.

Ask by topic name, enter viva, or use a numbered source range.
END_WRITE_TOPICS_1
            ;;
        2)
            cat <<'END_WRITE_TOPICS_2'
Topics for Practical 2

Process and thread
A process has a virtual address space and its own resources. Threads of one process share that address space and many resources, while each has its own stack and registers. Shared data needs synchronization when a thread can modify it.

System call
A controlled entry from a user program into the kernel. A C library wrapper such as read() normally provides a convenient way to invoke it. printf() is a library function that can eventually call write().

Process ID
PID identifies a process in its PID namespace. PPID identifies its current parent. getpid() and getppid() query those IDs. Reparenting changes PPID while the child's PID stays the same.

fork()
fork creates one child from the caller. It returns 0 in the child and the child's PID in the parent. -1 signals failure with no new child. Memory changes after fork are normally separate; open descriptors can still refer to the same kernel resources.

Copy-on-write
Linux can initially share memory pages across fork. A write causes a private copy of that page where needed. This gives each process independent logical memory without eagerly copying every page.

waitpid()
waitpid waits for a selected child and retrieves a status. WIFEXITED checks for a normal exit before WEXITSTATUS reads the exit code. Successfully waiting on an exited child also releases its remaining process-table record.

waitid() and WNOWAIT
waitid reports the selected child's state. WEXITED selects exit events. WNOWAIT leaves that event available for a later wait. The zombie demo uses those flags, prints the child's PID, then reaps it with waitpid.

Zombie process
A zombie is a child that has already exited but whose status is still waiting to be collected. It has no executing program. Only the retained process record remains until the parent or later adopter waits.

Orphan process
An orphan is a still-running child whose original parent has exited. A subreaper or init in its PID namespace can become its new parent. The demo detects the change by comparing old and new PPID values.

Buffered output
Standard I/O can hold output in a user-space buffer. fflush(stdout) pushes pending output toward the underlying stream. Flushing before fork avoids duplicated prompts. Line buffering emits output when a newline is printed.

Bubble Sort
Compare neighbors and swap those in the wrong order. Each pass moves a largest remaining element toward the end. The implementation uses roughly O(n^2) comparisons and O(1) extra sorting storage.

Selection Sort
At each step find the smallest value in the unsorted part and exchange it with the first unsorted element. It uses O(n^2) comparisons and O(1) extra sorting storage.

Ask by topic name, enter viva, or use a numbered source range.
END_WRITE_TOPICS_2
            ;;
        3)
            cat <<'END_WRITE_TOPICS_3'
Topics for Practical 3

Producer-consumer
The producer publishes items and the consumer removes them. empty counts free slots and full counts queued items. Start them at 5 and 0 for a five-slot empty buffer. Posting the opposite semaphore signals a change in availability.

Counting semaphore
A counting semaphore tracks permits. sem_wait takes one or blocks when none are available; sem_post releases one and can wake a waiter. sem_init with pshared = 0 shares it among threads of this process. Destroy it after threads finish.

Mutex
A mutex allows one thread at a time to enter a protected region. The locking thread normally unlocks it. It protects buffer access in Practical 3, while the semaphores enforce buffer capacity and item availability.

Critical section
A critical section reads or updates shared state that could otherwise be accessed incompatibly. Keep it short. Practical 3 acquires the mutex around storage access and the associated display.

Race condition
Program behavior can depend incorrectly on timing when concurrent operations use shared state without protection. In C, an unsynchronized conflicting memory access with at least one write is a data race and gives undefined behavior.

Circular buffer
A fixed array is reused cyclically. The expression i % BUFFER_SIZE turns a growing counter into a valid slot index. In a five-slot array index 5 wraps to 0. Semaphores ensure that slot is free before an overwrite.

Thread creation and joining
pthread_create starts a function in another thread and returns its thread handle through an argument. pthread_join waits for a joinable thread to finish. Join both workers before destroying synchronization objects they might use.

Concurrency and parallelism
Concurrency means several activities can make overlapping progress, even on one CPU through time sharing. Parallelism means activities actually run at the same instant on different execution units. Thread and process print order can depend on scheduling.

Ask by topic name, enter viva, or use a numbered source range.
END_WRITE_TOPICS_3
            ;;
        4)
            cat <<'END_WRITE_TOPICS_4'
Topics for Practical 4

Dining philosophers
Five threads around a table each need two adjacent forks. Use one permit for each fork and at most four simultaneous fork contenders. The limit prevents an all-five circular wait. It does not guarantee fairness.

Counting semaphore
A counting semaphore tracks permits. sem_wait takes one or blocks when none are available; sem_post releases one and can wake a waiter. sem_init with pshared = 0 shares it among threads of this process. Destroy it after threads finish.

Deadlock
Deadlock means a group cannot progress because each participant waits for resources another group member holds. The four classic conditions are mutual exclusion, hold-and-wait, no preemption, and circular wait.

Starvation and fairness
A participant starves if it is postponed indefinitely while others continue. Fairness is about how opportunities are assigned. A solution can eliminate deadlock without guaranteeing fairness.

Thread creation and joining
pthread_create starts a function in another thread and returns its thread handle through an argument. pthread_join waits for a joinable thread to finish. Join both workers before destroying synchronization objects they might use.

Concurrency and parallelism
Concurrency means several activities can make overlapping progress, even on one CPU through time sharing. Parallelism means activities actually run at the same instant on different execution units. Thread and process print order can depend on scheduling.

Ask by topic name, enter viva, or use a numbered source range.
END_WRITE_TOPICS_4
            ;;
        5)
            cat <<'END_WRITE_TOPICS_5'
Topics for Practical 5

Banker's algorithm
The safety check simulates completing one eligible process at a time. A full resource-request algorithm would tentatively grant a request, test safety, and either keep the allocation or undo it. This practical demonstrates the safety check.

Resource matrices
Allocation is already assigned, Max is the upper limit, and Need = Max - Allocation. Available represents unused resources. Work starts as Available; Finish tracks simulated completion. After a completion, Work gains that process's existing Allocation.

Safe sequence
A safe sequence is an order in which each process can satisfy its declared remainder and then release resources for later ones. An unsafe state has no such guaranteed order. It may still continue if the worst-case demands never occur.

Deadlock
Deadlock means a group cannot progress because each participant waits for resources another group member holds. The four classic conditions are mutual exclusion, hold-and-wait, no preemption, and circular wait.

Starvation and fairness
A participant starves if it is postponed indefinitely while others continue. Fairness is about how opportunities are assigned. A solution can eliminate deadlock without guaranteeing fairness.

Ask by topic name, enter viva, or use a numbered source range.
END_WRITE_TOPICS_5
            ;;
        6)
            cat <<'END_WRITE_TOPICS_6'
Topics for Practical 6

Interprocess communication
IPC lets independent processes exchange data or coordinate. This set uses pipes. Other OS mechanisms include shared memory, message queues, sockets and signals.

Named pipe (FIFO)
A FIFO has a filesystem pathname and carries a first-in-first-out byte stream through the kernel. Unrelated processes can open it by name. A blocking open waits for the corresponding reader or writer.

Duplex communication
Full duplex means both directions are possible simultaneously. Two pipes provide two independent directions. This program's request-response protocol sends one sentence and receives one reply before sending another.

C streams
FILE * is a C library stream with buffering. fopen opens a pathname; fdopen wraps an existing descriptor. fread and fwrite transfer bytes, fclose ends the stream, and fseek repositions a regular file. A FIFO itself cannot be sought.

Input lines and delimiters
getline reads up to a newline and grows a buffer when needed. getdelim allows a custom delimiter, in this practical a NUL byte after the pathname. A C string itself ends at a NUL character, written as '\0'.

Character, byte and word counting
strlen counts bytes before the NUL terminator. isspace identifies whitespace; an unsigned char cast makes the argument valid. Count a word whenever the stream changes from whitespace to a non-whitespace run. UTF-8 characters may occupy several bytes each.

Read and end of file
read returns a positive byte count, 0 at end of stream, or -1 on error. A pipe reaches EOF after all writer ends close and stored bytes are consumed. Ctrl+D on a blank Linux terminal line normally signals terminal end of input.

Ask by topic name, enter viva, or use a numbered source range.
END_WRITE_TOPICS_6
            ;;
        7)
            cat <<'END_WRITE_TOPICS_7'
Topics for Practical 7

Interprocess communication
IPC lets independent processes exchange data or coordinate. This set uses pipes. Other OS mechanisms include shared memory, message queues, sockets and signals.

Unnamed pipe
pipe() creates a pair with read end at index 0 and write end at index 1. Children can inherit the two ends from a parent. Close unused writers so readers can see end of stream.

fork()
fork creates one child from the caller. It returns 0 in the child and the child's PID in the parent. -1 signals failure with no new child. Memory changes after fork are normally separate; open descriptors can still refer to the same kernel resources.

File descriptor
A file descriptor is an integer reference to an open resource in a process. open returns a descriptor or -1; close releases that process's reference. O_RDONLY requests read-only access.

Partial writes
write returns the amount actually accepted. write_all advances past bytes already written and retries until complete. A finite pipe can make a writer block when a reader is not draining it. Read the reply before waiting for its writer to exit.

Read and end of file
read returns a positive byte count, 0 at end of stream, or -1 on error. A pipe reaches EOF after all writer ends close and stored bytes are consumed. Ctrl+D on a blank Linux terminal line normally signals terminal end of input.

Input lines and delimiters
getline reads up to a newline and grows a buffer when needed. getdelim allows a custom delimiter, in this practical a NUL byte after the pathname. A C string itself ends at a NUL character, written as '\0'.

waitpid()
waitpid waits for a selected child and retrieves a status. WIFEXITED checks for a normal exit before WEXITSTATUS reads the exit code. Successfully waiting on an exited child also releases its remaining process-table record.

Ask by topic name, enter viva, or use a numbered source range.
END_WRITE_TOPICS_7
            ;;
        8)
            cat <<'END_WRITE_TOPICS_8'
Topics for Practical 8

Disk scheduling
A request targets a cylinder in this simplified rotating-disk model. Every move adds the absolute cylinder difference to the total. Real timing also depends on device mechanics, rotation and transfer, so the printed figure here is a movement measure.

SSTF
Select the outstanding cylinder closest to the current head, then repeat from the new position. This code picks the earlier input item on equal distances. A far request may wait indefinitely under a stream of nearby requests.

SCAN
Serve requests in one direction, continue to the disk endpoint, reverse, and serve remaining ones. This practical starts toward the maximum. LOOK would reverse at the final request instead of visiting the physical endpoint.

C-LOOK
C-LOOK serves in one direction, wraps between extreme requested cylinders, and continues in its original direction. It avoids physical endpoints unless requested. C-SCAN instead wraps between physical ends. This practical counts wrap movement.

qsort and comparator
qsort sorts an array in place. The comparator returns a negative number for first < second, zero for equality, and a positive number for first > second. Comparing without a subtraction avoids possible integer overflow.

Overflow and bounds
Array indices must stay inside the declared capacity. Arithmetic outside the supported range can overflow. The disk program bounds request count and uses long long for movement, because the sum can exceed the maximum int value.

Ask by topic name, enter viva, or use a numbered source range.
END_WRITE_TOPICS_8
            ;;
        *) return 1 ;;
    esac
}


write_viva() {
    case $1 in
        1)
            cat <<'END_WRITE_VIVA_1'
Q. What is the difference between > and >>?
A. > truncates or creates the file. >> appends or creates it.

Q. Why quote a filename?
A. Quotes keep whitespace and wildcard characters inside one argument.

Q. Why use a temporary file?
A. The original remains intact while the updated version is being prepared.

Q. Why use IFS= with read -r for a name?
A. An empty IFS avoids trimming leading or trailing field separators. The
   -r flag prevents a backslash from being interpreted as an escape.

Q. Why use printf with a fixed format string?
A. User input is then passed as data to %s. Spaces and percent characters
   inside a name are written literally.

Q. Why does the program use the name and the field delimiter together?
A. The delimiter marks the end of the name. Searching just for the start
   of a name could confuse Ann with Anna or match a different field.

Q. Is this a database with a unique record key?
A. It is a plain text file keyed by the exact name for edit operations.
   Duplicate names are possible and are filtered together.

Q. How do you demonstrate persistence?
A. Insert a contact, exit, restart in the same folder and view the book.
   The contact is still in addressbook.txt.
END_WRITE_VIVA_1
            ;;
        2)
            cat <<'END_WRITE_VIVA_2'
Q. What does fork return?
A. 0 to the child, the child's PID to the parent, and -1 to the caller on failure.

Q. Why fflush before fork?
A. Any pending stdio buffer is copied by fork. Flushing prevents two copies of the prompt.

Q. Who adopts an orphan?
A. A Linux subreaper can adopt it, or the init process for its PID namespace.

Q. Why do zombies matter?
A. The child no longer runs, but its exit information occupies a process-table entry until collected.

Q. Which branch knows the child's PID immediately after fork()?
A. The parent. Its return value is the child's PID. The child's return
   value is 0, so it can call getpid() to print its own PID.

Q. Do the two sorts run on one shared array?
A. Both see the same initial values but each sees its own address space.
   Copy-on-write preserves isolation when one writes to a memory page.

Q. Why use waitpid(child, ...) rather than merely sleeping?
A. It waits for the intended child and collects its status. A fixed delay
   cannot tell whether the child finished, failed or is still running.

Q. How does WNOWAIT help demonstrate a zombie?
A. It observes the child's exit while leaving it waitable. waitpid() then
   collects the exit status so the example does not leave a zombie behind.

Q. If the orphan's PPID changes, does its PID also change?
A. No. Reparenting changes who supervises it. The same child continues.
END_WRITE_VIVA_2
            ;;
        3)
            cat <<'END_WRITE_VIVA_3'
Q. Can a mutex replace both semaphores?
A. It protects a shared operation, but does not count items or free slots. The threads would still need a way to wait for those conditions.

Q. What does sem_wait do at zero?
A. It blocks until a permit is available. With a positive count it takes one permit.

Q. Why use i % 5?
A. It wraps position 5 back to slot 0 so the sixth item can reuse the first slot safely.

Q. Why wait before locking?
A. A blocked thread should leave the mutex available so the other thread can change the buffer.

Q. What happens if the consumer starts before the producer?
A. full is 0, so the consumer blocks at its semaphore wait. The producer
   can still lock the mutex, write the first item and post full.

Q. What happens when all five slots are occupied?
A. empty is 0. The producer waits until the consumer returns a permit.

Q. Why does the sixth item go to index 0?
A. The sixth operation uses zero-based index 5, and 5 modulo 5 is 0. Its
   empty permit guarantees some space and FIFO order makes slot 0 reusable.

Q. Why can the output order differ but the consumed values stay ordered?
A. Scheduling interleaves the threads differently. Each thread processes
   its own increasing index and the semaphore order protects availability.

Q. Does sem_post() release the mutex?
A. No. sem_post() returns a semaphore permit. pthread_mutex_unlock()
   releases the mutex that protects the shared section.
END_WRITE_VIVA_3
            ;;
        4)
            cat <<'END_WRITE_VIVA_4'
Q. How can deadlock occur with five permits?
A. Each philosopher can hold their left fork and wait forever for the right fork held by a neighbor.

Q. Does deadlock freedom imply starvation freedom?
A. No. A particular philosopher could repeatedly lose access even while other philosophers complete meals.

Q. Which deadlock condition is broken?
A. The four-person room limit prevents a circular wait across all five forks in this acquisition order.

Q. What does a semaphore value of 1 mean for a fork?
A. One philosopher may acquire it. A second must wait until the first
   posts the permit.

Q. Why is philosopher 5's right fork 1?
A. The code uses a zero-based index and computes (left + 1) modulo 5.
   Adding 1 to the displayed index gives fork 1 after fork 5.

Q. Can two philosophers eat at the same time?
A. Yes, if they use disjoint pairs of forks. Adjacent philosophers share
   one fork and cannot eat together.

Q. How do deadlock and starvation differ?
A. Deadlock means the waiting cycle cannot advance. Starvation means one
   participant waits indefinitely even though others may keep eating.

Q. Why does the program need Ctrl+C?
A. Each thread runs an infinite demonstration loop, so the normal run
   has no final iteration or keyboard input.
END_WRITE_VIVA_4
            ;;
        5)
            cat <<'END_WRITE_VIVA_5'
Q. Is unsafe the same as deadlocked?
A. No. Unsafe means a safe completion order cannot be guaranteed for the stated maximum claims.

Q. Why add Allocation rather than Max to Work?
A. The remaining Need was hypothetically borrowed from Work and returned. The net gain is only the resources that were already allocated.

Q. Does this program grant a new request?
A. It implements the safety check. A full Banker implementation tentatively applies a request, checks safety, then grants it or rolls it back.

Q. Can a process finish if Need equals Work?
A. Yes. The comparison is Need <= Work in every resource type. It fails
   only if at least one required amount is larger than what is available.

Q. Why is P2 initially ineligible?
A. P2 needs 2 units of A but the initial Work vector has only 1 unit of A.
   After P0 finishes and releases its allocation, more A is available.

Q. Is the printed safe sequence unique?
A. No. There can be several orders that let every process finish. This
   implementation returns the one found by its left-to-right scans.

Q. What does a pass with no new Finish flag mean?
A. Every unfinished process still needs more than Work in at least one
   resource. Without a completion, Work cannot grow and the state is unsafe.

Q. Are the program's matrices real resource allocations?
A. They are a fixed snapshot used by the example. The safety simulation
   updates Work and Finish while leaving the supplied snapshot unchanged.
END_WRITE_VIVA_5
            ;;
        6)
            cat <<'END_WRITE_VIVA_6'
Q. What is the difference between a FIFO and a regular file?
A. A FIFO is a stream carried by the kernel. The pathname identifies the channel, but bytes are not stored like normal file contents.

Q. Why two FIFOs?
A. Each provides one direction in this design and keeps the request stream separate from the reply.

Q. Why does opening a FIFO sometimes appear to hang?
A. A blocking read or write open waits for the other endpoint to open the same FIFO.

Q. What is a word here?
A. One contiguous run of non-whitespace bytes. A punctuation mark next to a letter stays in that word.

Q. Why use two FIFOs for this design?
A. fifo1 carries requests from Process 1 to Process 2. fifo2 carries the
   report back. Separate channels let each pair open the proper endpoints.

Q. What can cause a FIFO open to hang?
A. A blocking read or write open can wait for the opposite endpoint.
   The launcher creates both pipes and starts both processes.

Q. How many words are in "one   two"?
A. Two. Consecutive whitespace clears the in-word flag repeatedly.
   Only the transition to non-whitespace starts a new word.

Q. Does pressing Enter add a byte to the character count?
A. No. The line ending used to send the request is removed before the
   sentence is analyzed.

Q. What happens to earlier analysis reports?
A. The latest analysis overwrites report.txt. The terminal can still show
   earlier reports in its scrollback history.
END_WRITE_VIVA_6
            ;;
        7)
            cat <<'END_WRITE_VIVA_7'
Q. What is a file descriptor?
A. A small process-local integer representing an open file or stream. pipe returns one for each end.

Q. Why drain the pipe before waitpid?
A. If the parent waits first and the pipe fills, the child blocks while writing and cannot exit.

Q. When does read return zero on the pipe?
A. Once the buffer is empty and every descriptor referring to its write end has been closed.

Q. What does pipe() return through its array?
A. Two file descriptors. Index 0 is the read end and index 1 is the write end.

Q. Why create both pipes before fork()?
A. The child inherits both sets of open descriptors and can use them to
   communicate with the parent without a filesystem name.

Q. Why is the pathname sent with a NUL byte?
A. The child uses that byte as the message delimiter and can then pass
   the resulting C string to open().

Q. Can read() or write() handle fewer bytes than requested?
A. Yes. read() reports the bytes it received. write_all() advances by
   the amount written and keeps going until the chunk is sent or fails.

Q. Which side must drain data before calling waitpid()?
A. The parent. If it waits while pipe2 is full, the child cannot finish
   writing and neither side can advance.
END_WRITE_VIVA_7
            ;;
        8)
            cat <<'END_WRITE_VIVA_8'
Q. How does SCAN differ from LOOK?
A. SCAN reaches a physical end before reversing in this exercise. LOOK reverses at the last request in that direction.

Q. Could SSTF starve a distant request?
A. Yes. If nearer requests keep arriving, the distant one may be postponed.

Q. Why does 57 appear twice?
A. The first 57 is the start position. The second is a request serviced there with zero movement.

Q. Does total seek time mean milliseconds?
A. Here it is total cylinder movement, used as a simplified measure. Physical seek time is device-dependent.

Q. Is the first 57 in the path a serviced request?
A. The first number shows the starting head position. The following 57
   is a request at that position and adds zero movement.

Q. Why can C-LOOK travel farther than SSTF for a particular input?
A. C-LOOK follows a directional ordering. SSTF makes a locally shortest
   choice each time. The total depends on the request distribution.

Q. Where does SCAN reverse in this program?
A. It travels toward the highest cylinder first and reverses at the given
   physical maximum. C-LOOK jumps from the highest queued position in
   its pass to the lowest remaining request.

Q. How is total movement calculated for C-LOOK?
A. Add the absolute difference between adjacent printed positions. This
   program includes the wrap from 102 to 10, which contributes 92.

Q. Why could SSTF starve far-away requests in a live system?
A. If nearby requests keep arriving, a distant request may repeatedly lose
   the next selection. The finite classroom input eventually runs out.
END_WRITE_VIVA_8
            ;;
        *) return 1 ;;
    esac
}


write_manual() {
    case $1 in
        1)
            cat <<'END_WRITE_MANUAL_1'
Manual run
bash practical1.sh

Sample
Choose 1, then 3. Enter Asha Patil, 9876543210, and Pune on separate lines. Then choose 2.
END_WRITE_MANUAL_1
            ;;
        2)
            cat <<'END_WRITE_MANUAL_2'
Manual run
gcc practical2.c -o practical2 && ./practical2

Sample
Enter 6, then 2 9 7 5 6 1. Run the optional zombie and orphan modes separately.
END_WRITE_MANUAL_2
            ;;
        3)
            cat <<'END_WRITE_MANUAL_3'
Manual run
gcc practical3.c -pthread -o practical3 && ./practical3

Sample
No input. Run the program once.
END_WRITE_MANUAL_3
            ;;
        4)
            cat <<'END_WRITE_MANUAL_4'
Manual run
gcc practical4.c -pthread -o practical4 && ./practical4

Sample
No input. Let it run until you see THINKING, picked LEFT/RIGHT fork, EATING and finished EATING.
END_WRITE_MANUAL_4
            ;;
        5)
            cat <<'END_WRITE_MANUAL_5'
Manual run
gcc practical5.c -o practical5 && ./practical5

Sample
No keyboard input. The code uses four processes, three resource types, and Available = (1, 1, 1).
END_WRITE_MANUAL_5
            ;;
        6)
            cat <<'END_WRITE_MANUAL_6'
Manual run
Terminal 1: gcc process1.c -o process1 && gcc process2.c -o process2 && mkfifo fifo1 fifo2 && ./process2
Terminal 2, in the same folder: ./process1
Create the FIFOs once. If they already exist as FIFOs, start ./process2 directly after compiling.

Sample
Enter Hello world! This is a FIFO full-duplex test. Then enter exit.
END_WRITE_MANUAL_6
            ;;
        7)
            cat <<'END_WRITE_MANUAL_7'
Manual run
gcc practical7.c -o practical7 && ./practical7

Sample
Create test.txt with printf 'Hello from a pipe.\n' > test.txt and enter test.txt at the program prompt.
END_WRITE_MANUAL_7
            ;;
        8)
            cat <<'END_WRITE_MANUAL_8'
Manual run
gcc practical8.c -o practical8 && ./practical8

Sample
Enter 8. Queue: 25 65 43 98 57 89 102 10. Head: 57. Maximum cylinder: 199.
END_WRITE_MANUAL_8
            ;;
        *) return 1 ;;
    esac
}


write_practical_help() {
    case $1 in
        1)
            cat <<'END_WRITE_PRACTICAL_HELP_1'
Create or insert before viewing. Match the literal saved name. Option 1 clears an existing address book.
END_WRITE_PRACTICAL_HELP_1
            ;;
        2)
            cat <<'END_WRITE_PRACTICAL_HELP_2'
Enter the count alone, then exactly that many integers. PIDs change each run. Zombie and orphan are the 2Z and 2O selections.
END_WRITE_PRACTICAL_HELP_2
            ;;
        3)
            cat <<'END_WRITE_PRACTICAL_HELP_3'
Keep -pthread on the compile command. If an older linker specifically cannot resolve sem_* symbols, append -lrt after the source.
END_WRITE_PRACTICAL_HELP_3
            ;;
        4)
            cat <<'END_WRITE_PRACTICAL_HELP_4'
The demo runs continuously. Press Ctrl+C after the first meals. Thread messages can appear in different orders.
END_WRITE_PRACTICAL_HELP_4
            ;;
        5)
            cat <<'END_WRITE_PRACTICAL_HELP_5'
This program uses fixed data and takes no input. The reference result is P0 -> P1 -> P2 -> P3.
END_WRITE_PRACTICAL_HELP_5
            ;;
        6)
            cat <<'END_WRITE_PRACTICAL_HELP_6'
Wait for the sentence prompt. Use exit to finish both processes. Reports go to report.txt in the working folder.
END_WRITE_PRACTICAL_HELP_6
            ;;
        7)
            cat <<'END_WRITE_PRACTICAL_HELP_7'
Use a readable local file. Make one with: printf 'Hello from a pipe.\n' > test.txt    Then enter test.txt.
END_WRITE_PRACTICAL_HELP_7
            ;;
        8)
            cat <<'END_WRITE_PRACTICAL_HELP_8'
Use 1 to 100 requests. Each cylinder and the head must be between zero and the stated maximum.
END_WRITE_PRACTICAL_HELP_8
            ;;
        *) return 1 ;;
    esac
}


write_recovery() {
    case $1 in
        ubuntu)
            cat <<'END_WRITE_RECOVERY_1'
Ubuntu lab PCs run Linux directly. Bring this one Bash file on your USB.
Copy it into a writable folder under Home and open it with Bash or Run as a Program.
Bash opens the menu. Only the C practicals need a Linux compiler such as GCC.
Choose Run a practical and T to check that the lab PC can run all eight samples.
Then choose the assigned number. The assistant saves and opens its source, and launches the run terminal.
END_WRITE_RECOVERY_1
            ;;
        gcc)
            cat <<'END_WRITE_RECOVERY_2'
Find a Linux compiler: command -v gcc cc clang; gcc --version
Offline, with the necessary packages cached:
  sudo apt-get --no-download --no-remove install build-essential
If your lab supplied all the matching .deb files, open that package folder:
  sudo apt-get --no-download --no-remove install ./*.deb
If headers or dependencies are missing from both places, use a prepared Ubuntu PC.
Online later: sudo apt-get update && sudo apt-get install build-essential
END_WRITE_RECOVERY_2
            ;;
        files)
            cat <<'END_WRITE_RECOVERY_3'
Check location and case-sensitive filenames: pwd; ls -l
Check disk space and folder permissions: df -h . /tmp; ls -ld . /tmp
For a read-only USB, copy the assistant into a writable folder under Home and open it there.
For Practical 7, type a readable file's full path without shell quotes at the program prompt.
END_WRITE_RECOVERY_3
            ;;
        encoding)
            cat <<'END_WRITE_RECOVERY_4'
A Bash file starts with #!/usr/bin/env bash. Keep this file's .sh extension and open it with Bash.
This launcher repairs Windows line endings automatically when started with Bash.
If the downloaded file starts with Length:, is HTML, or shows wget progress, it is not the launcher.
Get the raw file again or use your clean offline USB copy.
Check the file before running it: head -n 2 os-practicals.sh
The assistant writes source files with Unix/LF endings.
END_WRITE_RECOVERY_4
            ;;
        fifo)
            cat <<'END_WRITE_RECOVERY_5'
Use option 6 in the assistant to create private FIFOs and start both processes.
For a manual run, use two terminals open in the same folder. Start ./process2 first, then ./process1.
Check the endpoints: ls -l fifo1 fifo2    Both items should have p as the first character.
If regular files already use those names, use a fresh local folder and run: mkfifo fifo1 fifo2
Type exit in Process 1 to finish. For no output after a file-open error, use a writable local folder.
END_WRITE_RECOVERY_5
            ;;
        *) return 1 ;;
    esac
}


write_explanations() {
    case $1 in
        practical1.sh)
            cat <<'END_WRITE_EXPLANATIONS_1'
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Blank line separates related code. It has no runtime action.
Delete/modify a literal name using a temporary file. This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Read keyboard input and keep backslashes literal. IFS= also keeps whitespace at the ends.
Blank line separates related code. It has no runtime action.
Test a condition or select a branch. Read the condition together with the controlled operation.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
Test a condition or select a branch. Read the condition together with the controlled operation.
Blank line separates related code. It has no runtime action.
Create a unique temporary file for changes before replacing the address book.
Filter records by a literal name and field separator at the start of a line. Other records are copied unchanged.
Filter records by a literal name and field separator at the start of a line. Other records are copied unchanged.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Redirect output into the named file. A single > can create or truncate it.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Test a condition or select a branch. Read the condition together with the controlled operation.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Test a condition or select a branch. Read the condition together with the controlled operation.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Test a condition or select a branch. Read the condition together with the controlled operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
Test a condition or select a branch. Read the condition together with the controlled operation.
Blank line separates related code. It has no runtime action.
Test a condition or select a branch. Read the condition together with the controlled operation.
Test a condition or select a branch. Read the condition together with the controlled operation.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Read keyboard input and keep backslashes literal. IFS= also keeps whitespace at the ends.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Read keyboard input and keep backslashes literal. IFS= also keeps whitespace at the ends.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Read keyboard input and keep backslashes literal. IFS= also keeps whitespace at the ends.
Append a record to the file without clearing earlier lines.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
Test a condition or select a branch. Read the condition together with the controlled operation.
Test a condition or select a branch. Read the condition together with the controlled operation.
Blank line separates related code. It has no runtime action.
Move the staged file into the address-book pathname only after its contents are ready.
Test a condition or select a branch. Read the condition together with the controlled operation.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Test a condition or select a branch. Read the condition together with the controlled operation.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Test a condition or select a branch. Read the condition together with the controlled operation.
Test a condition or select a branch. Read the condition together with the controlled operation.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Test a condition or select a branch. Read the condition together with the controlled operation.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
The repeating menu and its operations. Repeat the block using the given condition or iteration. Check what value changes each time.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Read keyboard input and keep backslashes literal. IFS= also keeps whitespace at the ends.
Blank line separates related code. It has no runtime action.
Select or end one menu branch based on the user's current choice.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Redirect output into the named file. A single > can create or truncate it.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Test a condition or select a branch. Read the condition together with the controlled operation.
Select or end one menu branch based on the user's current choice.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Test a condition or select a branch. Read the condition together with the controlled operation.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Test a condition or select a branch. Read the condition together with the controlled operation.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Test a condition or select a branch. Read the condition together with the controlled operation.
Select or end one menu branch based on the user's current choice.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Read keyboard input and keep backslashes literal. IFS= also keeps whitespace at the ends.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Read keyboard input and keep backslashes literal. IFS= also keeps whitespace at the ends.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Read keyboard input and keep backslashes literal. IFS= also keeps whitespace at the ends.
Append a record to the file without clearing earlier lines.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Test a condition or select a branch. Read the condition together with the controlled operation.
Select or end one menu branch based on the user's current choice.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
Select or end one menu branch based on the user's current choice.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Select or end one menu branch based on the user's current choice.
This keyword marks the beginning or end of the shell control construct.
END_WRITE_EXPLANATIONS_1
            ;;
        practical2.c)
            cat <<'END_WRITE_EXPLANATIONS_2'
POSIX headers. Expose POSIX declarations in the system headers before they are included.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Blank line separates related code. It has no runtime action.
Parent's Bubble Sort. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Repeat the block using the given condition or iteration. Check what value changes each time.
Repeat the block using the given condition or iteration. Check what value changes each time.
Test a condition or select a branch. Read the condition together with the controlled operation.
Declare a value or function used in this block. Initializers set the value used before the first update.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Child's Selection Sort. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Repeat the block using the given condition or iteration. Check what value changes each time.
Declare a value or function used in this block. Initializers set the value used before the first update.
Repeat the block using the given condition or iteration. Check what value changes each time.
Test a condition or select a branch. Read the condition together with the controlled operation.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
This punctuation opens or closes the enclosing block or ends a statement.
Declare a value or function used in this block. Initializers set the value used before the first update.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Print sorted values. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Repeat the block using the given condition or iteration. Check what value changes each time.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Wait for and reap a child. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Declare a value or function used in this block. Initializers set the value used before the first update.
Wait for this child and obtain its exit status. An EINTR check lets the code retry.
Check or report a reason for a failed system or library operation.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Observe a zombie before reaping. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Make a child. The child receives zero and the parent receives the child's PID.
Test a condition or select a branch. Read the condition together with the controlled operation.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Test a condition or select a branch. Read the condition together with the controlled operation.
End the child immediately without flushing any duplicated stdio buffers or running exit handlers.
Blank line separates related code. It has no runtime action.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Declare a value or function used in this block. Initializers set the value used before the first update.
Repeat the block using the given condition or iteration. Check what value changes each time.
Inspect the child's exit event. With WNOWAIT, a later wait must still collect it.
Check or report a reason for a failed system or library operation.
Test a condition or select a branch. Read the condition together with the controlled operation.
Check or report a reason for a failed system or library operation.
Test a condition or select a branch. Read the condition together with the controlled operation.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Blank line separates related code. It has no runtime action.
Test a condition or select a branch. Read the condition together with the controlled operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
Wait for this child and obtain its exit status. An EINTR check lets the code retry.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Create an orphan and observe reparenting. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Declare a value or function used in this block. Initializers set the value used before the first update.
Create read and write file descriptors for a byte stream. Linux assigns read to index 0 and write to index 1.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Make a child. The child receives zero and the parent receives the child's PID.
Test a condition or select a branch. Read the condition together with the controlled operation.
Check or report a reason for a failed system or library operation.
Close this process's descriptor. Closing unused writer ends is needed for the reader to detect EOF.
Close this process's descriptor. Closing unused writer ends is needed for the reader to detect EOF.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Test a condition or select a branch. Read the condition together with the controlled operation.
Close this process's descriptor. Closing unused writer ends is needed for the reader to detect EOF.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Make a child. The child receives zero and the parent receives the child's PID.
Test a condition or select a branch. Read the condition together with the controlled operation.
Check or report a reason for a failed system or library operation.
End the child immediately without flushing any duplicated stdio buffers or running exit handlers.
This punctuation opens or closes the enclosing block or ends a statement.
Test a condition or select a branch. Read the condition together with the controlled operation.
End the child immediately without flushing any duplicated stdio buffers or running exit handlers.
Blank line separates related code. It has no runtime action.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Read the current parent's PID. Comparing with the old parent shows reparenting.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Control when buffered output is displayed. Flushing also avoids duplicating buffered text across fork.
Close this process's descriptor. Closing unused writer ends is needed for the reader to detect EOF.
End the child immediately without flushing any duplicated stdio buffers or running exit handlers.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Close this process's descriptor. Closing unused writer ends is needed for the reader to detect EOF.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Repeat the block using the given condition or iteration. Check what value changes each time.
Retrieve bytes from the descriptor. Check the count for data, end of stream, or an error.
Check or report a reason for a failed system or library operation.
Close this process's descriptor. Closing unused writer ends is needed for the reader to detect EOF.
Test a condition or select a branch. Read the condition together with the controlled operation.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Parse mode, read input, fork, and run the two sorts. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Compare two C strings. A return of zero means their bytes match.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
Compare two C strings. A return of zero means their bytes match.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
Test a condition or select a branch. Read the condition together with the controlled operation.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Declare a value or function used in this block. Initializers set the value used before the first update.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Control when buffered output is displayed. Flushing also avoids duplicating buffered text across fork.
Parse input and store values at the supplied addresses. Check how many conversions succeeded.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Allocate the requested number of bytes dynamically. The pointer is checked before the allocation is used.
Test a condition or select a branch. Read the condition together with the controlled operation.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Control when buffered output is displayed. Flushing also avoids duplicating buffered text across fork.
Repeat the block using the given condition or iteration. Check what value changes each time.
Parse input and store values at the supplied addresses. Check how many conversions succeeded.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Free the allocated buffer when it is no longer needed.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Control when buffered output is displayed. Flushing also avoids duplicating buffered text across fork.
Make a child. The child receives zero and the parent receives the child's PID.
Test a condition or select a branch. Read the condition together with the controlled operation.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Free the allocated buffer when it is no longer needed.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Test a condition or select a branch. Read the condition together with the controlled operation.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Free the allocated buffer when it is no longer needed.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Test a condition or select a branch. Read the condition together with the controlled operation.
Free the allocated buffer when it is no longer needed.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Free the allocated buffer when it is no longer needed.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
END_WRITE_EXPLANATIONS_2
            ;;
        practical3.c)
            cat <<'END_WRITE_EXPLANATIONS_3'
Shared data, buffer capacity and synchronization. Expose POSIX declarations in the system headers before they are included.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Blank line separates related code. It has no runtime action.
Define a named compile-time value such as a buffer size or count.
Blank line separates related code. It has no runtime action.
Access an element in the array. In the producer-consumer code the index wraps at the capacity.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Blank line separates related code. It has no runtime action.
Take a semaphore permit, retrying interruptions. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Take one permit or block until it becomes available. In these examples the permit represents space, an item, a fork, or a room entry.
Check or report a reason for a failed system or library operation.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Producer stores items. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Declare a value or function used in this block. Initializers set the value used before the first update.
Repeat the block using the given condition or iteration. Check what value changes each time.
Take one permit or block until it becomes available. In these examples the permit represents space, an item, a fork, or a room entry.
Enter the mutex-protected critical section. A competing thread waits if the lock is held.
Modulo wraps the position back to the first slot/fork after the last one.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Leave the critical section and let another thread acquire the mutex.
Return or publish one permit so a waiting thread can continue.
This punctuation opens or closes the enclosing block or ends a statement.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Consumer removes items. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Declare a value or function used in this block. Initializers set the value used before the first update.
Repeat the block using the given condition or iteration. Check what value changes each time.
Take one permit or block until it becomes available. In these examples the permit represents space, an item, a fork, or a room entry.
Enter the mutex-protected critical section. A competing thread waits if the lock is held.
Modulo wraps the position back to the first slot/fork after the last one.
Leave the critical section and let another thread acquire the mutex.
Return or publish one permit so a waiting thread can continue.
This punctuation opens or closes the enclosing block or ends a statement.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Report POSIX thread errors. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Test a condition or select a branch. Read the condition together with the controlled operation.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Set up semaphores and threads, join and clean up. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Set up the semaphore and its starting permit count. A zero pshared value means threads in this process use it.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Set up the semaphore and its starting permit count. A zero pshared value means threads in this process use it.
Check or report a reason for a failed system or library operation.
Release the synchronization object's resources after its users have finished.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Start a worker thread using the supplied start function and an optional argument.
Start a worker thread using the supplied start function and an optional argument.
Wait until this worker exits before proceeding with shutdown.
Wait until this worker exits before proceeding with shutdown.
Blank line separates related code. It has no runtime action.
Release the synchronization object's resources after its users have finished.
Release the synchronization object's resources after its users have finished.
Release the synchronization object's resources after its users have finished.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
END_WRITE_EXPLANATIONS_3
            ;;
        practical4.c)
            cat <<'END_WRITE_EXPLANATIONS_4'
Resources shared by the five threads. Expose POSIX declarations in the system headers before they are included.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Blank line separates related code. It has no runtime action.
Define a named compile-time value such as a buffer size or count.
Blank line separates related code. It has no runtime action.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Blank line separates related code. It has no runtime action.
Wait for a resource without losing an interrupted wait. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Take one permit or block until it becomes available. In these examples the permit represents space, an item, a fork, or a room entry.
Check or report a reason for a failed system or library operation.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
One philosopher thinks, obtains forks, eats, and releases resources. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Declare a value or function used in this block. Initializers set the value used before the first update.
Modulo wraps the position back to the first slot/fork after the last one.
Declare a value or function used in this block. Initializers set the value used before the first update.
Blank line separates related code. It has no runtime action.
Repeat the block using the given condition or iteration. Check what value changes each time.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Blank line separates related code. It has no runtime action.
Take one permit or block until it becomes available. In these examples the permit represents space, an item, a fork, or a room entry.
Take one permit or block until it becomes available. In these examples the permit represents space, an item, a fork, or a room entry.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Blank line separates related code. It has no runtime action.
Take one permit or block until it becomes available. In these examples the permit represents space, an item, a fork, or a room entry.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Blank line separates related code. It has no runtime action.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Blank line separates related code. It has no runtime action.
Return or publish one permit so a waiting thread can continue.
Return or publish one permit so a waiting thread can continue.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Blank line separates related code. It has no runtime action.
Return or publish one permit so a waiting thread can continue.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This punctuation opens or closes the enclosing block or ends a statement.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Limit fork contenders to four, then run five philosophers. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Declare a value or function used in this block. Initializers set the value used before the first update.
Control when buffered output is displayed. Flushing also avoids duplicating buffered text across fork.
Blank line separates related code. It has no runtime action.
Set up the semaphore and its starting permit count. A zero pshared value means threads in this process use it.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Repeat the block using the given condition or iteration. Check what value changes each time.
Set up the semaphore and its starting permit count. A zero pshared value means threads in this process use it.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Repeat the block using the given condition or iteration. Check what value changes each time.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Start a worker thread using the supplied start function and an optional argument.
Test a condition or select a branch. Read the condition together with the controlled operation.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Repeat the block using the given condition or iteration. Check what value changes each time.
Wait until this worker exits before proceeding with shutdown.
Blank line separates related code. It has no runtime action.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
END_WRITE_EXPLANATIONS_4
            ;;
        practical5.c)
            cat <<'END_WRITE_EXPLANATIONS_5'
Headers, process count, and resource-type count. Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Blank line separates related code. It has no runtime action.
Define a named compile-time value such as a buffer size or count.
Define a named compile-time value such as a buffer size or count.
Blank line separates related code. It has no runtime action.
Calculate Need and initialize the safety simulation. Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Update a control flag for the safety check, so it can identify eligible processes and detect progress.
Blank line separates related code. It has no runtime action.
Repeat the block using the given condition or iteration. Check what value changes each time.
Repeat the block using the given condition or iteration. Check what value changes each time.
Calculate the remaining resource requirement for this process and resource type.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Repeat the block using the given condition or iteration. Check what value changes each time.
Find a process that can finish and release its allocation. Set or update a value, or compare it when the operator is ==, !=, <= or >=.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Declare a value or function used in this block. Initializers set the value used before the first update.
Repeat the block using the given condition or iteration. Check what value changes each time.
Update a control flag for the safety check, so it can identify eligible processes and detect progress.
Blank line separates related code. It has no runtime action.
Repeat the block using the given condition or iteration. Check what value changes each time.
Test a condition or select a branch. Read the condition together with the controlled operation.
Update a control flag for the safety check, so it can identify eligible processes and detect progress.
Blank line separates related code. It has no runtime action.
Repeat the block using the given condition or iteration. Check what value changes each time.
Reject this candidate on the current pass if it needs more than the simulated pool has.
Update a control flag for the safety check, so it can identify eligible processes and detect progress.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Test a condition or select a branch. Read the condition together with the controlled operation.
Repeat the block using the given condition or iteration. Check what value changes each time.
Return the completed process's original allocation to the simulated pool.
This punctuation opens or closes the enclosing block or ends a statement.
Record a process in the order the safety simulation finds it can finish.
Update a control flag for the safety check, so it can identify eligible processes and detect progress.
Update a control flag for the safety check, so it can identify eligible processes and detect progress.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Report an unsafe state if a scan cannot make progress. Blank line separates related code. It has no runtime action.
Test a condition or select a branch. Read the condition together with the controlled operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Fixed sample values and display of the result. Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Blank line separates related code. It has no runtime action.
Declare a value or function used in this block. Initializers set the value used before the first update.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Declare a value or function used in this block. Initializers set the value used before the first update.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This punctuation opens or closes the enclosing block or ends a statement.
Declare a value or function used in this block. Initializers set the value used before the first update.
Blank line separates related code. It has no runtime action.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Blank line separates related code. It has no runtime action.
Test a condition or select a branch. Read the condition together with the controlled operation.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Repeat the block using the given condition or iteration. Check what value changes each time.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
This punctuation opens or closes the enclosing block or ends a statement.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
END_WRITE_EXPLANATIONS_5
            ;;
        practical7.c)
            cat <<'END_WRITE_EXPLANATIONS_6'
Headers and buffer setting. Expose POSIX declarations in the system headers before they are included.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Blank line separates related code. It has no runtime action.
Define a named compile-time value such as a buffer size or count.
Blank line separates related code. It has no runtime action.
Write a complete message even when write() accepts only part. Send bytes to a file descriptor. write_all loops until every byte has been sent or an error occurs.
This punctuation opens or closes the enclosing block or ends a statement.
Declare a value or function used in this block. Initializers set the value used before the first update.
Repeat the block using the given condition or iteration. Check what value changes each time.
Send bytes to a file descriptor. write_all loops until every byte has been sent or an error occurs.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
Test a condition or select a branch. Read the condition together with the controlled operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Child reads the path and sends the requested bytes. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Open or wrap an I/O stream. A read/write mode determines what the program can do; opening a FIFO may wait for its other endpoint.
Test a condition or select a branch. Read the condition together with the controlled operation.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Read up to the requested delimiter and grow the buffer if necessary. Here the sent pathname ends with a NUL.
Close the library stream and flush any pending writes.
Test a condition or select a branch. Read the condition together with the controlled operation.
Free the allocated buffer when it is no longer needed.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Declare a value or function used in this block. Initializers set the value used before the first update.
Free the allocated buffer when it is no longer needed.
Test a condition or select a branch. Read the condition together with the controlled operation.
Declare a value or function used in this block. Initializers set the value used before the first update.
Send bytes to a file descriptor. write_all loops until every byte has been sent or an error occurs.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Access an element in the array. In the producer-consumer code the index wraps at the capacity.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Repeat the block using the given condition or iteration. Check what value changes each time.
Retrieve bytes from the descriptor. Check the count for data, end of stream, or an error.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
Test a condition or select a branch. Read the condition together with the controlled operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
Send bytes to a file descriptor. write_all loops until every byte has been sent or an error occurs.
Check or report a reason for a failed system or library operation.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Test a condition or select a branch. Read the condition together with the controlled operation.
Check or report a reason for a failed system or library operation.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
This punctuation opens or closes the enclosing block or ends a statement.
Close this process's descriptor. Closing unused writer ends is needed for the reader to detect EOF.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Create both pipes and fork. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Create read and write file descriptors for a byte stream. Linux assigns read to index 0 and write to index 1.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Create read and write file descriptors for a byte stream. Linux assigns read to index 0 and write to index 1.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Make a child. The child receives zero and the parent receives the child's PID.
Test a condition or select a branch. Read the condition together with the controlled operation.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Test a condition or select a branch. Read the condition together with the controlled operation.
Close this process's descriptor. Closing unused writer ends is needed for the reader to detect EOF.
Close this process's descriptor. Closing unused writer ends is needed for the reader to detect EOF.
Declare a value or function used in this block. Initializers set the value used before the first update.
Close this process's descriptor. Closing unused writer ends is needed for the reader to detect EOF.
End the child immediately without flushing any duplicated stdio buffers or running exit handlers.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Parent reads and sends the pathname. Close this process's descriptor. Closing unused writer ends is needed for the reader to detect EOF.
Close this process's descriptor. Closing unused writer ends is needed for the reader to detect EOF.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Control when buffered output is displayed. Flushing also avoids duplicating buffered text across fork.
Read a line, growing the buffer if needed. A negative result signals EOF or an input error.
Declare a value or function used in this block. Initializers set the value used before the first update.
Blank line separates related code. It has no runtime action.
Test a condition or select a branch. Read the condition together with the controlled operation.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Test a condition or select a branch. Read the condition together with the controlled operation.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Send bytes to a file descriptor. write_all loops until every byte has been sent or an error occurs.
Check or report a reason for a failed system or library operation.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Free the allocated buffer when it is no longer needed.
Close this process's descriptor. Closing unused writer ends is needed for the reader to detect EOF.
Blank line separates related code. It has no runtime action.
Test a condition or select a branch. Read the condition together with the controlled operation.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Access an element in the array. In the producer-consumer code the index wraps at the capacity.
Repeat the block using the given condition or iteration. Check what value changes each time.
Retrieve bytes from the descriptor. Check the count for data, end of stream, or an error.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
Test a condition or select a branch. Read the condition together with the controlled operation.
Test a condition or select a branch. Read the condition together with the controlled operation.
Check or report a reason for a failed system or library operation.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
This punctuation opens or closes the enclosing block or ends a statement.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Read, write, or reposition a C stream. The arguments specify bytes, counts and which open stream to use.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
This punctuation opens or closes the enclosing block or ends a statement.
Close this process's descriptor. Closing unused writer ends is needed for the reader to detect EOF.
Blank line separates related code. It has no runtime action.
Wait and inspect the child's exit status. Declare a value or function used in this block. Initializers set the value used before the first update.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Repeat the block using the given condition or iteration. Check what value changes each time.
Wait for this child and obtain its exit status. An EINTR check lets the code retry.
Check or report a reason for a failed system or library operation.
Test a condition or select a branch. Read the condition together with the controlled operation.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Test a condition or select a branch. Read the condition together with the controlled operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
END_WRITE_EXPLANATIONS_6
            ;;
        practical8.c)
            cat <<'END_WRITE_EXPLANATIONS_7'
Headers, capacity and distance calculation. Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Blank line separates related code. It has no runtime action.
Define a named compile-time value such as a buffer size or count.
Blank line separates related code. It has no runtime action.
Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Return the absolute distance after calculating it in a type wide enough to hold the difference.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
SSTF chooses the nearest request. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Blank line separates related code. It has no runtime action.
Repeat the block using the given condition or iteration. Check what value changes each time.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Repeat the block using the given condition or iteration. Check what value changes each time.
Declare a value or function used in this block. Initializers set the value used before the first update.
Test a condition or select a branch. Read the condition together with the controlled operation.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
This punctuation opens or closes the enclosing block or ends a statement.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Record a move and print the next cylinder. Add the movement to the seek total, update the current cylinder, and print the new position.
This punctuation opens or closes the enclosing block or ends a statement.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
SCAN goes to the maximum cylinder and reverses. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Blank line separates related code. It has no runtime action.
Repeat the block using the given condition or iteration. Check what value changes each time.
Test a condition or select a branch. Read the condition together with the controlled operation.
Add the movement to the seek total, update the current cylinder, and print the new position.
This punctuation opens or closes the enclosing block or ends a statement.
Add the movement to the seek total, update the current cylinder, and print the new position.
Repeat the block using the given condition or iteration. Check what value changes each time.
Test a condition or select a branch. Read the condition together with the controlled operation.
Add the movement to the seek total, update the current cylinder, and print the new position.
This punctuation opens or closes the enclosing block or ends a statement.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
C-LOOK wraps to the lowest pending request. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Blank line separates related code. It has no runtime action.
Repeat the block using the given condition or iteration. Check what value changes each time.
Test a condition or select a branch. Read the condition together with the controlled operation.
Add the movement to the seek total, update the current cylinder, and print the new position.
This punctuation opens or closes the enclosing block or ends a statement.
Repeat the block using the given condition or iteration. Check what value changes each time.
Test a condition or select a branch. Read the condition together with the controlled operation.
Add the movement to the seek total, update the current cylinder, and print the new position.
This punctuation opens or closes the enclosing block or ends a statement.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Compare two requests for sorting. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Read and validate inputs, then run the algorithms. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Declare a value or function used in this block. Initializers set the value used before the first update.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Parse input and store values at the supplied addresses. Check how many conversions succeeded.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Repeat the block using the given condition or iteration. Check what value changes each time.
Parse input and store values at the supplied addresses. Check how many conversions succeeded.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Parse input and store values at the supplied addresses. Check how many conversions succeeded.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Parse input and store values at the supplied addresses. Check how many conversions succeeded.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Repeat the block using the given condition or iteration. Check what value changes each time.
Test a condition or select a branch. Read the condition together with the controlled operation.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Sort the request array once so SCAN and C-LOOK can traverse it in cylinder order.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
END_WRITE_EXPLANATIONS_7
            ;;
        process1.c)
            cat <<'END_WRITE_EXPLANATIONS_8'
POSIX setup. Expose POSIX declarations in the system headers before they are included.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Blank line separates related code. It has no runtime action.
Process 1 entry point and the FIFO filenames. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Test a condition or select a branch. Read the condition together with the controlled operation.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Blank line separates related code. It has no runtime action.
Read a sentence and send it through fifo1. Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Repeat the block using the given condition or iteration. Check what value changes each time.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Control when buffered output is displayed. Flushing also avoids duplicating buffered text across fork.
Read a line, growing the buffer if needed. A negative result signals EOF or an input error.
Declare a value or function used in this block. Initializers set the value used before the first update.
Test a condition or select a branch. Read the condition together with the controlled operation.
Repeat the block using the given condition or iteration. Check what value changes each time.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Open or wrap an I/O stream. A read/write mode determines what the program can do; opening a FIFO may wait for its other endpoint.
Test a condition or select a branch. Read the condition together with the controlled operation.
Check or report a reason for a failed system or library operation.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Close the library stream and flush any pending writes.
Check or report a reason for a failed system or library operation.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Compare two C strings. A return of zero means their bytes match.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
Blank line separates related code. It has no runtime action.
Open or wrap an I/O stream. A read/write mode determines what the program can do; opening a FIFO may wait for its other endpoint.
Read and display the reply from fifo2. Test a condition or select a branch. Read the condition together with the controlled operation.
Check or report a reason for a failed system or library operation.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Access an element in the array. In the producer-consumer code the index wraps at the capacity.
Declare a value or function used in this block. Initializers set the value used before the first update.
Read, write, or reposition a C stream. The arguments specify bytes, counts and which open stream to use.
Read, write, or reposition a C stream. The arguments specify bytes, counts and which open stream to use.
Test a condition or select a branch. Read the condition together with the controlled operation.
Check or report a reason for a failed system or library operation.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
This punctuation opens or closes the enclosing block or ends a statement.
Close the library stream and flush any pending writes.
Test a condition or select a branch. Read the condition together with the controlled operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Free the line buffer and finish. Free the allocated buffer when it is no longer needed.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
END_WRITE_EXPLANATIONS_8
            ;;
        process2.c)
            cat <<'END_WRITE_EXPLANATIONS_9'
Headers for stream I/O and text analysis. Expose POSIX declarations in the system headers before they are included.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Include declarations and constants from this header so the C compiler can check their use.
Blank line separates related code. It has no runtime action.
Count bytes, words and lines. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Declare a value or function used in this block. Initializers set the value used before the first update.
Measure the number of bytes before the terminating NUL in this C string.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Repeat the block using the given condition or iteration. Check what value changes each time.
Declare a value or function used in this block. Initializers set the value used before the first update.
Test a condition or select a branch. Read the condition together with the controlled operation.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Test whether this byte is whitespace. Whitespace ends the current word.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Write the report file and copy it into the reply stream. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Declare a value or function used in this block. Initializers set the value used before the first update.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Blank line separates related code. It has no runtime action.
Open or wrap an I/O stream. A read/write mode determines what the program can do; opening a FIFO may wait for its other endpoint.
Test a condition or select a branch. Read the condition together with the controlled operation.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Control when buffered output is displayed. Flushing also avoids duplicating buffered text across fork.
Check or report a reason for a failed system or library operation.
Close the library stream and flush any pending writes.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Access an element in the array. In the producer-consumer code the index wraps at the capacity.
Declare a value or function used in this block. Initializers set the value used before the first update.
Read, write, or reposition a C stream. The arguments specify bytes, counts and which open stream to use.
Read, write, or reposition a C stream. The arguments specify bytes, counts and which open stream to use.
Check or report a reason for a failed system or library operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Test a condition or select a branch. Read the condition together with the controlled operation.
Check or report a reason for a failed system or library operation.
Close the library stream and flush any pending writes.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Process 2 receives requests and sends replies until exit. Declare a value or function used in this block. Initializers set the value used before the first update.
This punctuation opens or closes the enclosing block or ends a statement.
Test a condition or select a branch. Read the condition together with the controlled operation.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Declare a value or function used in this block. Initializers set the value used before the first update.
Blank line separates related code. It has no runtime action.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Control when buffered output is displayed. Flushing also avoids duplicating buffered text across fork.
Repeat the block using the given condition or iteration. Check what value changes each time.
Open or wrap an I/O stream. A read/write mode determines what the program can do; opening a FIFO may wait for its other endpoint.
Test a condition or select a branch. Read the condition together with the controlled operation.
Check or report a reason for a failed system or library operation.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
Read a line, growing the buffer if needed. A negative result signals EOF or an input error.
Close the library stream and flush any pending writes.
Test a condition or select a branch. Read the condition together with the controlled operation.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
Test a condition or select a branch. Read the condition together with the controlled operation.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Compare two C strings. A return of zero means their bytes match.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
Blank line separates related code. It has no runtime action.
Open or wrap an I/O stream. A read/write mode determines what the program can do; opening a FIFO may wait for its other endpoint.
Test a condition or select a branch. Read the condition together with the controlled operation.
Check or report a reason for a failed system or library operation.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
This line is part of the displayed section. Use nearby lines to read the enclosing statement or block.
Close the library stream and flush any pending writes.
Check or report a reason for a failed system or library operation.
Set or update a value, or compare it when the operator is ==, !=, <= or >=.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
This punctuation opens or closes the enclosing block or ends a statement.
Blank line separates related code. It has no runtime action.
Free the allocated buffer when it is no longer needed.
Produce formatted output. Match the percent specifiers to argument types, and use \n for a new line.
Change control flow. return leaves the function, exit ends the program, break leaves the loop, and continue moves to its next iteration.
This punctuation opens or closes the enclosing block or ends a statement.
END_WRITE_EXPLANATIONS_9
            ;;
        *) return 1 ;;
    esac
}


write_glossary() {
            cat <<'END_WRITE_GLOSSARY'
Operating system	operating system,os,kernel,operating system	The operating system manages processes, memory, files and devices. The kernel is its privileged core. User programs call it through system calls for operations such as creating a process or opening a file.
System call	system call,system calls,syscall,system call	A controlled entry from a user program into the kernel. A C library wrapper such as read() normally provides a convenient way to invoke it. printf() is a library function that can eventually call write().
Command line	command line,terminal,command line,console,tty	The terminal supplies keyboard input and displays output. Bash is a shell running inside it. Python or a C binary can run as a program launched from the shell. A GUI terminal window and a shell program are separate components.
Working directory	working directory,working directory,current folder,cwd,pwd,relative path,absolute path	Every process has a current directory. Relative filenames such as test.txt start there. Absolute Linux paths start at /. Type pwd to check your folder, ls to list it, and cd to move. Quote a path that contains spaces.
Bash script	bash script,bash,shell script,bash script,shebang,bin/bash	A text file containing shell commands. The first line #!/usr/bin/env bash tells Linux how to execute it when launched directly. bash practical1.sh explicitly starts Bash and only needs source read permission.
Redirection	redirection,redirection,redirect,truncate,append,stdout,standard output	A shell can direct output into a file. > creates or truncates; >> appends. Standard input is stream 0, normal output is stream 1, and error output is stream 2. A C program often accesses these through stdin, stdout and stderr.
Shell quotes	shell quotes,quote,quotes,quoting,expansion,wildcard,globbing	Double quotes allow expansion of values such as $file while keeping the resulting text together. Single quotes normally preserve characters literally. Quoting is important for spaces in filenames and user-entered text.
Shell read	shell read,read -r,ifs,shell read	Read a line into a shell variable. -r keeps backslashes literal; setting IFS= immediately before read preserves leading and trailing spaces. A failed read often means end of input.
Shell case and loop	shell case and loop,case,esac,while true,do,done,menu,shell flow	case selects the first matching pattern. ;; ends that branch and esac closes the case. while true repeats the menu until break, exit, or a read that fails.
AWK and literal matching	awk and literal matching,awk,index,environ,literal match,regex,regular expression	AWK reads one record at a time, normally a line. index(text, target) returns a one-based starting position or 0. In the address book matching index == 1 on the name plus delimiter finds an exact literal name at the start; characters like . have no regex meaning.
Temporary file	temporary file,mktemp,temp file,temporary file,mv	mktemp safely creates a fresh name. The address book builds the update in that file, then mv replaces the old file once the new contents are ready. Creating it in the same directory keeps the rename on the same filesystem.
File permissions	file permissions,permission,permissions,chmod,executable,noexec	Read permission lets the program open source, write permission on a directory lets it create entries, and execute permission lets Linux run a binary. A noexec mount can block execution even with execute bits set. bash file.sh reads a script through Bash.
Compiler and linker	compiler and linker,gcc,gcc command,compilation,compiler,linker,build-essential,pthread flag	GCC turns C source into machine code through preprocessing, compiling, assembly and linking. -o sets the executable name. -pthread supplies thread-related options during compilation and linking. Ubuntu's build-essential package provides the standard build toolchain.
Header file	header file,header,include,stdio.h,unistd.h,pthread.h,semaphore.h,sys/wait.h	A header exposes declarations and constants. stdio.h declares printf and FILE, unistd.h declares POSIX calls such as fork/read/write, sys/wait.h exposes wait interfaces, and pthread.h and semaphore.h declare synchronization APIs.
Process and thread	process and thread,process,processes,thread,threads,multithreading	A process has a virtual address space and its own resources. Threads of one process share that address space and many resources, while each has its own stack and registers. Shared data needs synchronization when a thread can modify it.
Concurrency and parallelism	concurrency and parallelism,concurrency,parallelism,concurrent,parallel,scheduling	Concurrency means several activities can make overlapping progress, even on one CPU through time sharing. Parallelism means activities actually run at the same instant on different execution units. Thread and process print order can depend on scheduling.
Process ID	process id,pid,ppid,getpid,getppid,pid_t,process id	PID identifies a process in its PID namespace. PPID identifies its current parent. getpid() and getppid() query those IDs. Reparenting changes PPID while the child's PID stays the same.
fork()	fork(),fork	fork creates one child from the caller. It returns 0 in the child and the child's PID in the parent. -1 signals failure with no new child. Memory changes after fork are normally separate; open descriptors can still refer to the same kernel resources.
Copy-on-write	copy-on-write,copy on write,cow,address space,virtual memory	Linux can initially share memory pages across fork. A write causes a private copy of that page where needed. This gives each process independent logical memory without eagerly copying every page.
waitpid()	waitpid(),wait,waitpid,wait_for_child,wifexited,wexitstatus,reap,reaping	waitpid waits for a selected child and retrieves a status. WIFEXITED checks for a normal exit before WEXITSTATUS reads the exit code. Successfully waiting on an exited child also releases its remaining process-table record.
waitid() and WNOWAIT	waitid() and wnowait,waitid,wnowait,wexited,siginfo_t	waitid reports the selected child's state. WEXITED selects exit events. WNOWAIT leaves that event available for a later wait. The zombie demo uses those flags, prints the child's PID, then reaps it with waitpid.
Zombie process	zombie process,zombie,defunct	A zombie is a child that has already exited but whose status is still waiting to be collected. It has no executing program. Only the retained process record remains until the parent or later adopter waits.
Orphan process	orphan process,orphan,reparent,adopt,subreaper,init	An orphan is a still-running child whose original parent has exited. A subreaper or init in its PID namespace can become its new parent. The demo detects the change by comparing old and new PPID values.
Buffered output	buffered output,buffered output,fflush,setvbuf,line buffered,iolbf,_iolbf	Standard I/O can hold output in a user-space buffer. fflush(stdout) pushes pending output toward the underlying stream. Flushing before fork avoids duplicated prompts. Line buffering emits output when a newline is printed.
Exit and signals	exit and signals,exit,_exit,exit_success,exit_failure,sigint,sigterm,ctrl+c	A process returns an exit status. exit flushes C streams and runs exit handlers; _exit ends immediately without those handlers. Ctrl+C normally sends SIGINT to the foreground process group. SIGTERM is a conventional request to terminate.
Interrupted system call	interrupted system call,eintr,errno,perror,interrupted system call	A blocking call can report EINTR after a signal interrupts it. Where appropriate the code retries. errno carries such error codes after failure, and perror translates the current number into a message. Check the return value first.
Bubble Sort	bubble sort,bubble sort,bubble_sort,adjacent swap	Compare neighbors and swap those in the wrong order. Each pass moves a largest remaining element toward the end. The implementation uses roughly O(n^2) comparisons and O(1) extra sorting storage.
Selection Sort	selection sort,selection sort,selection_sort,minimum index	At each step find the smallest value in the unsorted part and exchange it with the first unsorted element. It uses O(n^2) comparisons and O(1) extra sorting storage.
Counting semaphore	counting semaphore,semaphore,counting semaphore,sem_t,sem_init,sem_wait,sem_post,sem_destroy	A counting semaphore tracks permits. sem_wait takes one or blocks when none are available; sem_post releases one and can wake a waiter. sem_init with pshared = 0 shares it among threads of this process. Destroy it after threads finish.
Mutex	mutex,mutex,pthread_mutex_t,pthread_mutex_lock,pthread_mutex_unlock,lock,mutual exclusion	A mutex allows one thread at a time to enter a protected region. The locking thread normally unlocks it. It protects buffer access in Practical 3, while the semaphores enforce buffer capacity and item availability.
Critical section	critical section,critical section,shared data,shared buffer	A critical section reads or updates shared state that could otherwise be accessed incompatibly. Keep it short. Practical 3 acquires the mutex around storage access and the associated display.
Race condition	race condition,race condition,data race,unsynchronized	Program behavior can depend incorrectly on timing when concurrent operations use shared state without protection. In C, an unsynchronized conflicting memory access with at least one write is a data race and gives undefined behavior.
Producer-consumer	producer-consumer,producer,consumer,producer consumer,bounded buffer,empty,full	The producer publishes items and the consumer removes them. empty counts free slots and full counts queued items. Start them at 5 and 0 for a five-slot empty buffer. Posting the opposite semaphore signals a change in availability.
Circular buffer	circular buffer,circular buffer,ring buffer,modulo,wraparound,buffer_size	A fixed array is reused cyclically. The expression i % BUFFER_SIZE turns a growing counter into a valid slot index. In a five-slot array index 5 wraps to 0. Semaphores ensure that slot is free before an overwrite.
Thread creation and joining	thread creation and joining,pthread_create,pthread_join,pthread_t,join,thread id	pthread_create starts a function in another thread and returns its thread handle through an argument. pthread_join waits for a joinable thread to finish. Join both workers before destroying synchronization objects they might use.
Dining philosophers	dining philosophers,dining philosophers,philosopher,room semaphore,left fork,right fork	Five threads around a table each need two adjacent forks. Use one permit for each fork and at most four simultaneous fork contenders. The limit prevents an all-five circular wait. It does not guarantee fairness.
Deadlock	deadlock,deadlock,circular wait,coffman conditions,hold and wait,no preemption	Deadlock means a group cannot progress because each participant waits for resources another group member holds. The four classic conditions are mutual exclusion, hold-and-wait, no preemption, and circular wait.
Starvation and fairness	starvation and fairness,starvation,fairness,bounded waiting	A participant starves if it is postponed indefinitely while others continue. Fairness is about how opportunities are assigned. A solution can eliminate deadlock without guaranteeing fairness.
Banker's algorithm	banker's algorithm,banker,bankers,banker's algorithm,bankers algorithm,safety algorithm	The safety check simulates completing one eligible process at a time. A full resource-request algorithm would tentatively grant a request, test safety, and either keep the allocation or undo it. This practical demonstrates the safety check.
Resource matrices	resource matrices,allocation,available,max,maximum demand,need,work,finish,resource matrix	Allocation is already assigned, Max is the upper limit, and Need = Max - Allocation. Available represents unused resources. Work starts as Available; Finish tracks simulated completion. After a completion, Work gains that process's existing Allocation.
Safe sequence	safe sequence,safe sequence,safe state,unsafe state,unsafe	A safe sequence is an order in which each process can satisfy its declared remainder and then release resources for later ones. An unsafe state has no such guaranteed order. It may still continue if the worst-case demands never occur.
Interprocess communication	interprocess communication,ipc,interprocess communication,inter process communication	IPC lets independent processes exchange data or coordinate. This set uses pipes. Other OS mechanisms include shared memory, message queues, sockets and signals.
Named pipe (FIFO)	named pipe (fifo),named pipe,fifo,mkfifo,fifo1,fifo2	A FIFO has a filesystem pathname and carries a first-in-first-out byte stream through the kernel. Unrelated processes can open it by name. A blocking open waits for the corresponding reader or writer.
Unnamed pipe	unnamed pipe,unnamed pipe,anonymous pipe,pipe,pipe1,pipe2	pipe() creates a pair with read end at index 0 and write end at index 1. Children can inherit the two ends from a parent. Close unused writers so readers can see end of stream.
Duplex communication	duplex communication,duplex,full duplex,half duplex,request response	Full duplex means both directions are possible simultaneously. Two pipes provide two independent directions. This program's request-response protocol sends one sentence and receives one reply before sending another.
File descriptor	file descriptor,file descriptor,fd,close,open,o_rdonly	A file descriptor is an integer reference to an open resource in a process. open returns a descriptor or -1; close releases that process's reference. O_RDONLY requests read-only access.
C streams	c streams,file *,fopen,fclose,fdopen,fread,fwrite,fseek,report.txt,stdio	FILE * is a C library stream with buffering. fopen opens a pathname; fdopen wraps an existing descriptor. fread and fwrite transfer bytes, fclose ends the stream, and fseek repositions a regular file. A FIFO itself cannot be sought.
Partial writes	partial writes,partial write,write_all,write,short write,pipe capacity	write returns the amount actually accepted. write_all advances past bytes already written and retries until complete. A finite pipe can make a writer block when a reader is not draining it. Read the reply before waiting for its writer to exit.
Read and end of file	read and end of file,read,eof,end of file,ctrl+d	read returns a positive byte count, 0 at end of stream, or -1 on error. A pipe reaches EOF after all writer ends close and stored bytes are consumed. Ctrl+D on a blank Linux terminal line normally signals terminal end of input.
Input lines and delimiters	input lines and delimiters,getline,getdelim,delimiter,nul,null terminator,newline	getline reads up to a newline and grows a buffer when needed. getdelim allows a custom delimiter, in this practical a NUL byte after the pathname. A C string itself ends at a NUL character, written as '\0'.
Character, byte and word counting	character, byte and word counting,character count,bytes,word count,isspace,strlen,whitespace,encoding,utf-8	strlen counts bytes before the NUL terminator. isspace identifies whitespace; an unsigned char cast makes the argument valid. Count a word whenever the stream changes from whitespace to a non-whitespace run. UTF-8 characters may occupy several bytes each.
Pointers and arrays	pointers and arrays,pointer,array,dereference,address of,void *,argv,argc	An array stores elements in order. A pointer stores an address. &x obtains an address and *p accesses the pointed-to value. void * is a generic object pointer. argc counts command-line arguments and argv holds their strings.
Dynamic allocation	dynamic allocation,malloc,free,size_t,ssize_t,heap	malloc requests memory and returns its address, or NULL on failure. free releases it. size_t holds nonnegative sizes. ssize_t can also represent -1 to signal read-like operations failing.
Formatted input and output	formatted input and output,scanf,printf,fprintf,format specifier,%d,%zu,%jd,%lld	printf substitutes values into a format. scanf writes parsed values to addresses and returns how many conversions succeeded. %d represents int, %zu size_t, %jd intmax_t, and %lld long long. A mismatch can cause undefined behavior.
Disk scheduling	disk scheduling,disk scheduling,disk head,cylinder,seek,seek time,seek distance	A request targets a cylinder in this simplified rotating-disk model. Every move adds the absolute cylinder difference to the total. Real timing also depends on device mechanics, rotation and transfer, so the printed figure here is a movement measure.
SSTF	sstf,sstf,shortest seek time first,nearest request	Select the outstanding cylinder closest to the current head, then repeat from the new position. This code picks the earlier input item on equal distances. A far request may wait indefinitely under a stream of nearby requests.
SCAN	scan,scan,elevator algorithm,scan disk	Serve requests in one direction, continue to the disk endpoint, reverse, and serve remaining ones. This practical starts toward the maximum. LOOK would reverse at the final request instead of visiting the physical endpoint.
C-LOOK	c-look,c-look,clook,c look,circular look,c-scan,look	C-LOOK serves in one direction, wraps between extreme requested cylinders, and continues in its original direction. It avoids physical endpoints unless requested. C-SCAN instead wraps between physical ends. This practical counts wrap movement.
qsort and comparator	qsort and comparator,qsort,compare_ints,comparator,sorting comparator	qsort sorts an array in place. The comparator returns a negative number for first < second, zero for equality, and a positive number for first > second. Comparing without a subtraction avoids possible integer overflow.
Overflow and bounds	overflow and bounds,overflow,integer overflow,array bounds,long long,llabs,llong_max	Array indices must stay inside the declared capacity. Arithmetic outside the supported range can overflow. The disk program bounds request count and uses long long for movement, because the sum can exceed the maximum int value.
WSL	wsl,wsl,wsl.exe,windows subsystem for linux,ubuntu on windows	WSL can host a Linux distribution on Windows. A Windows Python interpreter can show the study menu by itself. To run the Linux practicals on Windows, WSL needs an installed Linux distribution and the same Bash/GCC tools used in the lab.
END_WRITE_GLOSSARY
}



prepare_sources() {
    local number=$1 original=$PWD candidate=$PWD file index=0 conflict
    local -a names
    mapfile -t names < <(practical_sources "$number")
    while :; do
        if (( index == 1 )); then
            candidate=$original/os_practical_$number
        elif (( index > 1 )); then
            candidate=$original/os_practical_${number}_$index
        fi
        if (( index )) && [[ -L $candidate || ( -e $candidate && ! -d $candidate ) ]]; then
            ((index += 1))
            continue
        fi
        [[ -d $candidate ]] || mkdir -- "$candidate" || return 1
        conflict=0
        for file in "${names[@]}"; do
            if [[ -L $candidate/$file ]] || { [[ -e $candidate/$file ]] &&
                { [[ ! -f $candidate/$file ]] || ! cmp -s -- "$candidate/$file" <(write_source "$file"); }; }; then
                conflict=1
                break
            fi
        done
        if (( conflict )); then
            ((index += 1))
            continue
        fi
        for file in "${names[@]}"; do
            if [[ ! -e $candidate/$file ]]; then
                (set -o noclobber; write_source "$file" > "$candidate/$file") || return 1
            fi
        done
        prepared_dir=$candidate
        return 0
    done
}

quote_command() {
    local item
    for item in "$@"; do
        if [[ $item == *"'"* ]]; then item=${item//\'/\'\\\'\'}; fi
        printf "'%s' " "$item"
    done
}

open_terminal() {
    local title=$1 folder=$2
    shift 2
    local executable terminal child shell_command directory pane source_command
    local -a flags args=("$BASH" "$script_path" "$@")
    directory=--working-directory=$folder
    shell_command=$(quote_command "${args[@]}")
    if [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
        for terminal in gnome-terminal ptyxis kgx xfce4-terminal x-terminal-emulator xterm; do
            executable=$(command -v "$terminal") || continue
            case $terminal in
                gnome-terminal) flags=(--window "$directory" "--title=$title" -- "${args[@]}") ;;
                ptyxis) flags=(--new-window "$directory" "--title=$title" -- "${args[@]}") ;;
                kgx) flags=("$directory" --command "$shell_command") ;;
                xfce4-terminal) flags=(--window "$directory" "--title=$title" --execute "${args[@]}") ;;
                x-terminal-emulator) flags=(-e "${args[@]}") ;;
                xterm) flags=(-T "$title" -e "${args[@]}") ;;
            esac
            if command -v setsid >/dev/null; then
                (cd -- "$folder" && exec setsid "$executable" "${flags[@]}") </dev/null >/dev/null 2>&1 &
            else
                (cd -- "$folder" && exec "$executable" "${flags[@]}") </dev/null >/dev/null 2>&1 &
            fi
            child=$!
            sleep 0.35
            if kill -0 "$child" 2>/dev/null || wait "$child"; then
                return 0
            fi
        done
    fi
    if [[ -n ${TMUX:-} ]] && command -v tmux >/dev/null; then
        pane=$(tmux new-window -P -F '#{pane_id}' -c "$folder" -n "$title" "$shell_command" 2>/dev/null) ||
            return 1
        if [[ $1 == --child ]]; then
            source_command=$(quote_command "$BASH" "$script_path" --view "$2")
            if ! tmux split-window -d -h -t "$pane" -c "$folder" "$source_command" >/dev/null 2>&1; then
                tmux split-window -d -v -t "$pane" -c "$folder" "$source_command" >/dev/null 2>&1 ||
                    printf '  Source saved. This tmux window is too small for a source pane.\n' >&2
            fi
        fi
        return 0
    fi
    return 1
}

open_editor() {
    local folder=$1 number=$2 editor executable file
    [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]] || return 1
    local -a files=()
    while IFS= read -r file; do files+=("$folder/$file"); done < <(practical_sources "$number")
    for editor in gnome-text-editor gedit mousepad xed kate pluma leafpad; do
        executable=$(command -v "$editor") || continue
        if command -v setsid >/dev/null; then
            setsid "$executable" "${files[@]}" </dev/null >/dev/null 2>&1 &
        else
            "$executable" "${files[@]}" </dev/null >/dev/null 2>&1 &
        fi
        return 0
    done
    if executable=$(command -v xdg-open); then
        for file in "${files[@]}"; do
            "$executable" "$file" </dev/null >/dev/null 2>&1 &
        done
        return 0
    fi
    return 1
}

view_saved_source() {
    local number=$1 mode=$2 file editor
    local -a files=()
    while IFS= read -r file; do files+=("./$file"); done < <(practical_sources "$number")
    if [[ -t 0 && -t 1 ]]; then
        if [[ $mode == edit ]]; then
            for editor in nano vim vi; do
                if command -v "$editor" >/dev/null; then
                    "$editor" "${files[@]}"
                    return
                fi
            done
        fi
        if command -v less >/dev/null; then
            less -N -- "${files[@]}"
            return
        fi
    fi
    for file in "${files[@]}"; do
        printf '\n--- %s ---\n' "${file#./}"
        cat -- "$file"
    done
}

single_terminal_choices() {
    local number=$1 mode=$2 folder=$3 reply
    while :; do
        printf '\n  [R] Run here   [V] View saved source   [0] Back\n'
        read_answer 'Choose > ' || return 0
        case ${reply,,} in
            r) (cd -- "$folder" && run_prepared "$number" "$mode"); return ;;
            v) (cd -- "$folder" && view_saved_source "$number" view) ;;
            0|'') return 0 ;;
        esac
    done
}

report_native_failure() {
    printf '\n  Run failed (status %s).\n' "$2" >&2
    printf '  %s\n' "$(write_practical_help "$1")" >&2
    printf '  See [D] in the menu for more offline help.\n' >&2
}

run_prepared() {
    local number=$1 mode=$2 status=0 data_file=''
    case $number in
        1) data_file=addressbook.txt ;;
        6) data_file=report.txt ;;
    esac
    if [[ -n $data_file && ( -L $data_file || ( -e $data_file && ! -f $data_file ) ) ]]; then
        printf '  %s needs to be a regular file. Copy the launcher to a different folder and try again.\n' "$data_file" >&2
        return 1
    fi
    printf '\nPractical %s  %s\n' "$number" "${titles[number]}"
    case $number in
        4) printf '%s\n' 'Press Ctrl+C after observing the demonstration.' ;;
        6) printf '%s\n' 'Enter a sentence, or type exit to finish. The latest report is in report.txt.' ;;
        7) printf '%s\n' 'Enter the full path of a readable text file.' ;;
    esac
    run_native "$number" "$mode" || status=$?
    if (( status && status != 130 )); then
        report_native_failure "$number" "$status"
    fi
    return "$status"
}

start_practical() {
    local number=$1 mode=$2 style=$3 prepared_dir
    case $(uname -s) in
        Linux) ;;
        *)
            printf '%s\n' '  Run the practical on the Ubuntu lab PC. Study and source export are available here.' >&2
            return 1
            ;;
    esac
    prepare_sources "$number" || {
        printf '%s\n' '  Could not save the source. Move this launcher into a writable folder under Home.' >&2
        return 1
    }
    local saved
    saved=$(practical_sources "$number")
    printf '\n  Saved  %s\n' "${saved//$'\n'/, }"
    [[ $prepared_dir == "$PWD" ]] || printf '  Folder  %s\n' "$prepared_dir"
    if [[ $style != here ]] && open_editor "$prepared_dir" "$number"; then
        printf '  Opening the source in the text editor.\n'
    fi
    if [[ $style == here ]]; then
        (cd -- "$prepared_dir" && run_prepared "$number" "$mode")
    elif open_terminal "OS Practical $number" "$prepared_dir" --child "$number" "$mode"; then
        printf '  Practical %s opened in a separate terminal.\n' "$number"
    else
        printf '  This session could not open a second terminal. Your source is saved.\n' >&2
        if [[ $style == menu ]]; then
            single_terminal_choices "$number" "$mode" "$prepared_dir"
        else
            printf '  Open the assistant menu for the Run here and View saved source options.\n' >&2
            return 1
        fi
    fi
}

extract_all() {
    local destination=$1 file
    mkdir -p -- "$destination" || return 1
    for file in "${sources[@]}"; do
        if [[ -e $destination/$file || -L $destination/$file ]]; then
            printf 'A file already exists: %s\n' "$destination/$file" >&2
            return 1
        fi
    done
    for file in "${sources[@]}"; do
        (set -o noclobber; write_source "$file" > "$destination/$file") || return 1
    done
    printf 'Saved all source files in %s\n' "$destination"
}



show_practicals() {
    local heading=$1 i width=${COLUMNS:-80}
    if [[ -t 1 ]] && command -v tput >/dev/null; then
        width=$(tput cols 2>/dev/null) || width=${COLUMNS:-80}
    fi
    printf '\n%s\n' "$heading"
    if [[ $width =~ ^[0-9]+$ ]] && (( width >= 65 )); then
        for i in 1 2 3 4; do
            printf '  [%d] %-24s   [%d] %s\n' "$i" "${titles[i]}" "$((i+4))" "${titles[i+4]}"
        done
    else
        for i in {1..8}; do printf '  [%d] %s\n' "$i" "${titles[i]}"; done
    fi
}

read_answer() {
    printf '%s' "$1"
    IFS= read -r reply
}

expanded_query() {
    local line file
    case $1 in
        paste)
            printf 'Paste the text, then type END alone on a new line.\n' >&2
            while IFS= read -r line; do
                [[ $line != END ]] || break
                printf '%s\n' "$line"
            done ;;
        clip)
            if [[ -n ${WAYLAND_DISPLAY:-} ]] && command -v wl-paste >/dev/null; then
                wl-paste --no-newline
            elif [[ -n ${DISPLAY:-} ]] && command -v xclip >/dev/null; then
                xclip -selection clipboard -o
            else
                printf 'Clipboard access is unavailable. Use paste or a line range.\n' >&2
            fi ;;
        "file "*)
            file=${1#file }
            if [[ -f $file && -r $file ]]; then
                head -c 65536 -- "$file"
            else
                printf 'Could not read that text file.\n' >&2
            fi ;;
        *) printf '%s\n' "$1" ;;
    esac
}

show_range() {
    local name=$1 first=$2 last=$3 i
    local -a lines explanations
    mapfile -t lines < <(write_source "$name")
    mapfile -t explanations < <(write_explanations "$name")
    if (( first < 1 || last < first || last > ${#lines[@]} )); then
        printf '%s has lines 1 through %d.\n' "$name" "${#lines[@]}"
        return 1
    fi
    printf '\n%s, lines %d-%d\n' "$name" "$first" "$last"
    for (( i=first; i<=last; i++ )); do
        printf '%3d  %s\n     %s\n' "$i" "${lines[i-1]}" "${explanations[i-1]}"
    done
}

find_snippet() {
    local name=$1 query=$2 range
    range=$(write_source "$name" | VIVA_QUERY="$query" awk '
        function norm(s) { gsub(/[[:space:]]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
        BEGIN { q = norm(ENVIRON["VIVA_QUERY"]) }
        { lines[NR] = norm($0) }
        END {
            if (length(q) < 3) exit
            for (i=1; i<=NR; i++) {
                if (length(lines[i]) == 0) continue
                item = lines[i]
                for (j=i; j<=NR && length(item)<=length(q); j++) {
                    if (item == q) { print i, j; exit }
                    if (index(q,item) != 1 || j == NR) break
                    if (length(lines[j+1])) item = item " " lines[j+1]
                }
            }
        }
    ')
    if [[ -n $range ]]; then
        local first last
        read -r first last <<< "$range"
        show_range "$name" "$first" "$last"
    else
        return 1
    fi
}

explain() {
    local number=$1 raw=$2 name first last part selected=
    local -a requests names
    mapfile -t names < <(practical_sources "$number")
    case $raw in
        topics|concepts) write_topics "$number"; return ;;
        overview|walkthrough|sample) write_walkthrough "$number"; return ;;
        paper) write_paper "$number"; return ;;
        viva|questions) write_viva "$number"; return ;;
        source|code) for name in "${names[@]}"; do
            printf '\n%s\n' "$name"; write_source "$name" | nl -ba
        done; return ;;
    esac
    if [[ $raw =~ ^([[:alnum:]_]+\.[[:alnum:]]+:)?[0-9] ]] && [[ $raw != *$'\n'* ]]; then
        IFS=, read -ra requests <<< "$raw"
        selected=${names[0]}
        local range_pattern='^[[:blank:]]*(([a-zA-Z0-9_.]+):)?([0-9]{1,6})(-([0-9]{1,6}))?[[:blank:]]*$'
        for part in "${requests[@]}"; do
            if [[ ! $part =~ $range_pattern ]]; then
                printf 'Use a line number or range, for example 10-18 or process2.c:25-40.\n'
                return 1
            fi
            selected=${BASH_REMATCH[2]:-$selected}
            first=${BASH_REMATCH[3]}
            last=${BASH_REMATCH[5]:-$first}
            name=
            for part in "${names[@]}"; do [[ $part != "$selected" ]] || name=$part; done
            if [[ -z $name ]]; then
                printf 'Choose a source file from: %s\n' "${names[*]}"
                return 1
            fi
            show_range "$name" "$((10#$first))" "$((10#$last))" || return
        done
        return 0
    fi
    for name in "${names[@]}"; do
        if [[ $raw == "$name" ]]; then write_source "$name" | nl -ba; return; fi
        if [[ $raw == *'('* || $raw == *'='* || $raw == *';'* || $raw == *$'\n'* ]]; then
            if find_snippet "$name" "$raw"; then return; fi
        fi
    done
    local answer
    answer=$(write_glossary | VIVA_QUERY="$raw" awk -F '\t' '
        function norm(s) {
            s = tolower(s)
            gsub(/[^a-z0-9_]+/, " ", s)
            sub(/^ /, "", s); sub(/ $/, "", s)
            return s
        }
        BEGIN { q = norm(ENVIRON["VIVA_QUERY"]); if (q == "") exit }
        {
            count = split($2, aliases, ",")
            for (i=1; i<=count; i++) {
                word = norm(aliases[i])
                if (word == "") continue
                if (q == word) { print $1 "\n" $3; exact = 1; exit }
                if (index(" " q " ", " " word " ")) {
                    if (found < 5) results[++found] = $1 "\n" $3
                    break
                }
            }
        }
        END { if (!exact) for (i=1; i<=found; i++) print results[i] "\n" }
    ')
    if [[ -n $answer ]]; then
        printf '\n%s\n' "$answer"
        return 0
    fi
    printf 'No match in the offline lessons. Try topics, viva, source, or a line range.\n'
}

study_menu() {
    local number=$1 reply query
    printf '\nPractical %s  %s\n' "$number" "${titles[number]}"
    printf '%s\n' 'Try walkthrough, topics, viva, source, paper, or a question.' \
        'For code, enter 10-18 or a filename and range. Use paste for several lines.'
    while read_answer 'Explain (0 = back) > ' && [[ $reply != 0 ]]; do
        query=$(expanded_query "$reply")
        [[ -z $query ]] || explain "$number" "$query"
    done
}

error_help() {
    local reply query topic
    printf '\nOffline error help\n  Enter ubuntu, compiler, files, encoding, fifo, or a practical number.\n'
    printf '  You can also paste an error. Use paste for several lines.\n'
    read_answer 'Topic or error (0 = back) > ' || return
    [[ $reply != 0 ]] || return
    query=$(expanded_query "$reply")
    case ${query,,} in
        [1-8])
            write_practical_help "$query"
            write_manual "$query"
            printf '\nChecks and walkthrough\n'
            write_walkthrough "$query"
            return ;;
        ubuntu|linux|lab|*'wsl'*) topic=ubuntu ;;
        compiler|gcc|*'gcc'*|*'clang'*|*'undefined reference'*|*'-std='*|*'no linux tool'*) topic=gcc ;;
        files|*'permission denied'*|*'no space left'*|*'read-only'*|*'no such file'*|*'could not open'*) topic=files ;;
        encoding|*'invalid decimal literal'*|*'[text/plain]'*|*'syntax error'*|*'bad interpreter'*|*'unexpected token'*) topic=encoding ;;
        fifo|*'fifo'*|*'broken pipe'*) topic=fifo ;;
        *)
            printf 'Try the practical number for its sample and manual steps. Check the first error above.\n'
            return ;;
    esac
    write_recovery "$topic"
}



self_test() (
    local folder number status output data mode
    if [[ $(uname -s) != Linux ]]; then
        printf 'Run the full test on the Ubuntu lab PC.\n'
        return 1
    fi
    if ! command -v timeout >/dev/null || ! command -v grep >/dev/null; then
        printf 'The full test needs timeout and grep. Try each practical manually on this PC.\n' >&2
        return 1
    fi
    folder=$(mktemp -d -- /tmp/os-practicals-test.XXXXXXXX) || return 1
    trap 'for file in "${sources[@]}" addressbook.txt report.txt sample.txt input.txt output.txt; do
        rm -f -- "$folder/$file"
    done
    rmdir -- "$folder"' EXIT
    trap 'exit 130' INT
    cd -- "$folder" || return 1
    for number in {1..8}; do
        prepare_sources "$number" || return 1
        mode=normal
        case $number in
            1) data=$'1\n3\nLab User\n1234\nPune\n2\n6\n' ;;
            2) data=$'6\n2 9 7 5 6 1\n' ;;
            3|5) data='' ;;
            4) data=''; mode=sample ;;
            6) data=$'Hello world! This is a FIFO full-duplex test.\nexit\n' ;;
            7)
                printf 'Hello from a pipe.\n' > sample.txt
                data=$'sample.txt\n' ;;
            8) data=$'8\n25 65 43 98 57 89 102 10\n57\n199\n' ;;
        esac
        printf '%s' "$data" > input.txt
        status=0
        timeout 40 "$BASH" "$script_path" --native "$number" "$mode" < input.txt > output.txt 2>&1 || status=$?
        if { [[ $number == 4 ]] && (( status != 124 )); } ||
            { [[ $number != 4 ]] && (( status != 0 )); }; then
            printf '\nFAIL %s (status %s)\n' "$number" "$status"
            cat output.txt
            return 1
        fi
        case $number in
            1) grep -Fq 'Lab User | 1234 | Pune' output.txt ;;
            2) [[ $(grep -Fc '1 2 5 6 7 9 ' output.txt) == 2 ]] ;;
            3) grep -Fq 'Consumed:6' output.txt ;;
            4) grep -Fq 'finished EATING' output.txt ;;
            5) grep -Fq 'P0 -> P1 -> P2 -> P3' output.txt ;;
            6) grep -Fq 'Total Characters: 45' output.txt && grep -Fq 'Total Words     : 8' report.txt ;;
            7) grep -Fq 'Hello from a pipe.' output.txt ;;
            8) output=$(grep -F 'Total seek time' output.txt)
               [[ $output == $'Total seek time = 155\nTotal seek time = 331\nTotal seek time = 170' ]] ;;
        esac
        if (( $? != 0 )); then
            printf '\nFAIL %s: sample output did not match.\n' "$number"
            cat output.txt
            return 1
        fi
        printf 'PASS %s  %s\n' "$number" "${titles[number]}"
    done
    printf 'All eight sample checks passed on this PC.\n'
)

run_menu() {
    local reply number mode
    while :; do
        show_practicals 'Run a practical'
        printf '\n  [0] Back   [D] Error help   [T] Test all\n  [2Z] Zombie demo   [2O] Orphan demo\n'
        read_answer 'Choose > ' || return
        mode=normal
        case ${reply,,} in
            0) return ;;
            d) error_help; continue ;;
            t) self_test; return ;;
            2z) number=2; mode=zombie ;;
            2o) number=2; mode=orphan ;;
            [1-8]) number=$reply ;;
            *) continue ;;
        esac
        start_practical "$number" "$mode" menu
        return
    done
}

main_menu() {
    local reply action
    printf '\nOS PRACTICALS ASSISTANT\nFolder  %s\n' "$PWD"
    while :; do
        printf '\n  [1] Run a practical\n  [2] Paper write-up\n  [3] Code explainer and viva\n  [0] Exit\n'
        read_answer 'Choose > ' || return 0
        action=$reply
        case $action in
            0) return 0 ;;
            1) run_menu ;;
            2|3)
                if [[ $action == 2 ]]; then show_practicals 'Paper write-up'
                else show_practicals 'Code explainer and viva'; fi
                printf '\n  [0] Back\n'
                read_answer 'Choose > ' || return 0
                if [[ $reply =~ ^[1-8]$ ]]; then
                    if [[ $action == 2 ]]; then write_paper "$reply"; else study_menu "$reply"; fi
                fi ;;
        esac
    done
}

usage() {
    cat <<'USAGE'
OS Practicals Assistant for Ubuntu. Run the file with Bash to open the menu.
  --extract [folder]       Save all nine source files.
  --paper NUMBER           Print the paper write-up.
  --here NUMBER [MODE]     Run in this terminal explicitly.
  --self-test              Check all eight on Ubuntu.
  NUMBER [MODE]            Open a practical in a separate terminal.
MODE is zombie or orphan for Practical 2.
USAGE
}

script_path=$(realpath -- "$0") || exit 1
case ${1:-} in
    '')
        if [[ ! -t 0 && ! -t 1 && /proc/$$/fd/0 -ef /dev/null ]] &&
            [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
            open_terminal 'OS Practicals' "$(dirname -- "$script_path")" --menu
            exit $?
        fi
        if [[ -t 0 && -t 1 && -z ${DISPLAY:-}${WAYLAND_DISPLAY:-}${TMUX:-} ]] &&
            command -v tmux >/dev/null; then
            menu_command=$(quote_command "$BASH" "$script_path" --menu)
            if tmux new-session -c "$PWD" -n 'OS Practicals' "$menu_command"; then
                exit 0
            fi
        fi
        main_menu ;;
    --menu) main_menu ;;
    --help|-h) usage ;;
    --extract) extract_all "${2:-os-practicals-source}" ;;
    --paper)
        if [[ ${2:-} =~ ^[1-8]$ ]]; then write_paper "$2"; else usage; exit 2; fi ;;
    --self-test) self_test ;;
    --view)
        if [[ ! ${2:-} =~ ^[1-8]$ ]]; then exit 2; fi
        view_saved_source "$2" edit ;;
    --child|--native)
        if [[ ! ${2:-} =~ ^[1-8]$ ]]; then exit 2; fi
        if [[ $1 == --native ]]; then run_native "$2" "${3:-normal}"; exit $?; fi
        status=0
        run_prepared "$2" "${3:-normal}" || status=$?
        if [[ -t 0 && -t 1 ]]; then read_answer $'\nPress Enter to close this terminal.'; fi
        exit "$status" ;;
    --here|[1-8])
        style=separate
        if [[ $1 == --here ]]; then style=here; shift; fi
        number=${1:-}
        mode=${2:-normal}
        if [[ $number =~ ^[1-8]$ ]] &&
            { [[ $mode == normal ]] || { [[ $number == 2 ]] && [[ $mode == zombie || $mode == orphan ]]; }; }; then
            start_practical "$number" "$mode" "$style"
        else
            usage
            exit 2
        fi ;;
    *) usage; exit 2 ;;
esac
