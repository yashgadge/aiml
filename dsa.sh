#!/usr/bin/env bash
# Self-contained Ubuntu / Git Bash on Windows launcher. No installations.

show_command() {
    printf '$'
    printf ' %q' "$@"
    printf '\n'
}

try_python() {
    local resolved output status
    local -a probe
    if [[ $1 == */* ]]; then
        resolved=$1
    else
        resolved=$(type -P -- "$1") || return 1
    fi
    [[ -f $resolved && -x $resolved ]] || return 1
    # Linux/WSL must use Linux Python; Git Bash must use native Windows Python.
    if [[ ${dsa_platform:-linux} == linux ]]; then
        case ${resolved,,} in *.exe|*.com|*.bat|*.cmd) return 1 ;; esac
    fi
    # Do not trigger the Windows Store's unconfigured Python execution alias.
    case ${resolved,,} in */microsoft/windowsapps/python*.exe) return 1 ;; esac
    probe=("$resolved" "${@:2}" -c "$python_probe")
    if [[ -n $probe_timeout ]]; then
        probe=("$probe_timeout" 5 "${probe[@]}")
    fi
    show_command "${probe[@]}"
    output=$("${probe[@]}" 2>&1)
    status=$?
    if [[ $status == 0 && $output == DSA_PYTHON_OK ]]; then
        python_cmd=("$resolved" "${@:2}")
        printf 'Using Python command:'
        printf ' %q' "${python_cmd[@]}"
        printf '\n'
        return 0
    fi
    printf 'That Python command is not usable (status %s). Trying the next candidate.\n' "$status"
    [[ -z $output ]] || printf '%s\n' "$output"
    return 1
}

select_python() {
    local folder candidate
    local -a folders
    python_cmd=()
    local expected=linux
    [[ ${dsa_platform:-linux} == windows ]] && expected=win32
    python_probe="import sys; sys.exit('Requires $expected Python 3.8 or newer') if sys.platform != '$expected' or sys.version_info < (3,8) else None; import argparse, pathlib, shlex, subprocess, tempfile, threading; print('DSA_PYTHON_OK')"
    probe_timeout=$(type -P timeout) || probe_timeout=''
    case ${probe_timeout,,} in *.exe|*.com|*.bat|*.cmd) probe_timeout='' ;; esac
    # Conventional names first, then standard absolute paths if PATH is broken.
    for candidate in python3 /usr/bin/python3 /usr/local/bin/python3 python py3; do
        try_python "$candidate" && return 0
    done
    if [[ ${dsa_platform:-linux} == windows ]]; then
        try_python py -3 && return 0
        # Cover installations whose folder was not added to PATH.
        for candidate in /c/Python3[0-9]*/python.exe /c/Users/*/AppData/Local/Programs/Python/Python3[0-9]*/python.exe; do
            [[ -f $candidate ]] || continue
            try_python "$candidate" && return 0
        done
    fi
    # Discover installed versioned interpreters, including future 3.x releases.
    IFS=: read -r -a folders <<< "$PATH"
    folders+=(/usr/bin /usr/local/bin)
    for folder in "${folders[@]}"; do
        [[ -n $folder ]] || folder=.
        for candidate in "$folder"/python3.[0-9]*; do
            [[ ${candidate##*/} =~ ^python3\.[0-9]+$ ]] || continue
            try_python "$candidate" && return 0
        done
    done
    # Some Linux installations provide a py launcher. Probe it rather than
    # assuming Windows-specific switches such as -3.14 are meaningful.
    try_python py -3 && return 0
    try_python py && return 0
    printf 'No usable %s Python 3.8+ interpreter was found.\n' "${dsa_platform:-linux}"
    printf 'If Python is installed, check its executable and PATH. Standard absolute paths were also checked.\n'
    if [[ ${dsa_platform:-linux} == windows ]]; then
        printf 'Install or repair Python 3 for Windows, enable its launcher or PATH option, and reopen Git Bash.\nNo packages are installed automatically.\n'
    else
        printf 'Run: sudo apt install python3\nThen start this launcher again.\n'
    fi
    return 127
}

# DSA_DETECTION_END: tests inspect the functions above without running a practical.
case $(uname -s) in
    Linux) dsa_platform=linux ;;
    MINGW*|MSYS*|CYGWIN*) dsa_platform=windows ;;
    *) printf 'Supported environments: Ubuntu/Linux Bash or Git Bash on Windows.\n'; exit 1 ;;
esac
bootstrap_log=$(mktemp "${TMPDIR:-/tmp}/dsa-startup.XXXXXXXX.log") || exit 1
if select_python > "$bootstrap_log" 2>&1; then
    export DSA_BOOTSTRAP_LOG=$bootstrap_log
else
    status=$?
    cat -- "$bootstrap_log"
    exit "$status"
fi
runner=$(mktemp "${TMPDIR:-/tmp}/dsa-launcher.XXXXXXXX.py") || {
    printf 'Cannot create launcher file. Check temporary-folder permissions and free space.\n'
    exit 1
}
trap 'rm -f -- "$runner"' EXIT
cat > "$runner" <<'DSA_PYTHON_PAYLOAD_2026'

#!/usr/bin/env python3
"""Offline DSA practical launcher. Python 3.8+, Ubuntu or Windows."""
import argparse
import errno
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import py_compile
from contextlib import redirect_stdout, redirect_stderr

LAST_SETUP_LOG = None

SOURCES = {'1': '#include <iostream>\n#include <cstdlib>\n#include <string>\n#include <vector>\n#include <sstream>\n#include <cmath>\n#include <new>\nusing namespace std;\n\n\n// Recover from malformed numeric tokens; EOF ends a redirected session cleanly.\ntemplate<class T> void readValue(T& value) {\n    std::string token;\n    while (std::cin >> token) {\n        std::istringstream parser(token);\n        char extra;\n        if ((parser >> value) && !(parser >> extra)) return;\n        std::cout << "Invalid input. Enter a valid number: ";\n    }\n    std::cout << "\\nInput ended.\\n";\n    std::exit(0);\n}\n\nstruct Student {\n    int id;\n    string name;\n    float cgpa;\n};\nvector<Student> students;\nint student_count = 0;\n\nvoid addStudent() {\n    int n;\n    cout << "\\nHow many students do you want to add? ";\n    readValue(n);\n    if (n <= 0 || n > 100000 - student_count) {\n        cout << "Enter a positive student_count; at most 100000 students in total.\\n";\n        return;\n    }\n    try { students.resize(student_count + n); }\n    catch (const bad_alloc&) { cout << "Memory Allocation Failed!\\n"; return; }\n    for (int i = 0; i < n; i++) {\n        cout << "\\nStudent" << student_count + 1 << endl;\n        cout << "Enter ID : ";\n        readValue(students[student_count].id);\n        cout << "Enter Name : ";\n        if (!(cin >> students[student_count].name)) { cout << "\\nInput ended.\\n"; return; }\n        cout << "Enter CGPA : ";\n        readValue(students[student_count].cgpa);\n        while (!isfinite(students[student_count].cgpa) || students[student_count].cgpa < 0 || students[student_count].cgpa > 10) {\n            cout << "CGPA must be between 0 and 10: ";\n            readValue(students[student_count].cgpa);\n        }\n        student_count++;\n    }\n    cout << "\\nStudents Added Successfully.\\n";\n}\n\nvoid displayStudents() {\n    if (student_count == 0) {\n        cout << "\\nNo Records Found.\\n";\n        return;\n    }\n    cout << "\\n==============================\\n";\n    cout << "Student Records\\n";\n    cout << "==============================\\n";\n    for (int i=0; i < student_count; i++) {\n        cout << "ID: " << students[i].id << endl;\n        cout << "Name: " << students[i].name << endl;\n        cout << "CGPA: " << students[i].cgpa << endl;\n        cout << "----------\\n";\n    }\n}\n\nvoid linearSearch() {\n    if (student_count == 0) {\n        cout << "\\nNo Records Found.\\n";\n        return;\n    }\n    int id;\n    int comparisons = 0;\n    cout << "\\nEnter Student ID : ";\n    readValue(id);\n    for (int i = 0; i < student_count; i++) {\n        comparisons++;\n        if (students[i].id == id) {\n            cout << "\\nStudent Found\\n";\n            cout << "ID: " << students[i].id << endl;\n            cout << "Name: " << students[i].name << endl;\n            cout << "CGPA: " << students[i].cgpa << endl;\n            cout << "Comparisons: " << comparisons << endl;\n            return;\n        }\n    }\n    cout << "\\nStudent Not Found.\\n";\n    cout << "Comparisons: " << comparisons << endl;\n}\n\nvoid sortByID() {\n    Student temp;\n    for (int i = 0; i < student_count - 1; i++) {\n        for (int j=0; j < student_count - 1; j++) {\n            if (students[j].id > students[j + 1].id) {\n                temp = students[j];\n                students[j] = students[j + 1];\n                students[j + 1] = temp;\n            }\n        }\n    }\n    cout << "\\nStudents Sorted by ID.\\n";\n}\n\nvoid binarySearch() {\n    if (student_count == 0) {\n        cout << "\\nNo Records Found.\\n";\n        return;\n    }\n    sortByID();\n    int id;\n    int low = 0;\n    int high = student_count - 1;\n    int comparisons = 0;\n    cout << "\\nEnter Student ID: ";\n    readValue(id);\n    while (low <= high) {\n        comparisons++;\n        int mid = low + (high - low) / 2;\n        if (students[mid].id == id) {\n            cout << "\\nStudent Found\\n";\n            cout << "ID: " << students[mid].id << endl;\n            cout << "Name: " << students[mid].name << endl;\n            cout << "CGPA: " << students[mid].cgpa << endl;\n            cout << "Comparisons: " << comparisons << endl;\n            return;\n        } else if (id < students[mid].id) {\n            high = mid - 1;\n        } else {\n            low = mid + 1;\n        }\n    }\n    cout << "\\nStudent Not Found.\\n";\n    cout << "Comparisons: " << comparisons << endl;\n}\n\nvoid bubbleSortName() {\n    Student temp;\n    for (int i=0; i < student_count - 1; i++) {\n        for (int j=0; j < student_count - 1; j++) {\n            if (students[j].name > students[j + 1].name) {\n                temp = students[j];\n                students[j] = students[j + 1];\n                students[j + 1] = temp;\n            }\n        }\n    }\n    cout << "\\nStudents Sorted by Name.\\n";\n}\n\nvoid selectionSortCGPA() {\n    Student temp;\n    for (int i=0; i < student_count - 1; i++) {\n        int max = i;\n        for (int j=i+1; j < student_count; j++) {\n            if (students[j].cgpa > students[max].cgpa) {\n                max = j;\n            }\n        }\n        temp = students[i];\n        students[i] = students[max];\n        students[max] = temp;\n    }\n    cout << "\\nStudents Sorted by CGPA (Descending).\\n";\n}\n\nvoid performanceComparison() {\n    if (student_count == 0) {\n        cout << "\\nNo Records Found.\\n";\n        return;\n    }\n    cout << "\\n==============================\\n";\n    cout << "Performance Comparison\\n";\n    cout << "===============================\\n";\n    cout << "Linear Search\\n";\n    cout << "Best Case: 1 Comparison\\n";\n    cout << "Worst Case: " << student_count << " Comparisons\\n\\n";\n    int steps = 0;\n    int n = student_count;\n    while (n>0) {\n        steps++;\n        n=n/2;\n    }\n    cout << "Binary Search\\n";\n    cout << "Best Case: 1 Comparison\\n";\n    cout << "Worst Case: " << steps << " Comparisons\\n\\n";\n    cout << "Linear Search Time Complexity: O(n)\\n";\n    cout << "Binary Search Time Complexity: O(log n)\\n";\n    cout << "Sorting before binary search uses O(n^2) time in this program.\\n";\n}\n\nint main() {\n    int choice;\n    do {\n        cout << "\\n=========== STUDENT DATABASE ===========\\n";\n        cout << "\\n1. Add Students";\n        cout << "\\n2. Display Students";\n        cout << "\\n3. Linear Search";\n        cout << "\\n4. Binary Search";\n        cout << "\\n5. Bubble Sort by Name";\n        cout << "\\n6. Selection Sort by CGPA";\n        cout << "\\n7. Compare Search Performance";\n        cout << "\\n8. Exit";\n        cout << "\\n\\nEnter Your Choice: ";\n        readValue(choice);\n        switch (choice) {\n            case 1: addStudent(); break;\n            case 2: displayStudents(); break;\n            case 3: linearSearch(); break;\n            case 4: binarySearch(); break;\n            case 5: bubbleSortName(); displayStudents(); break;\n            case 6: selectionSortCGPA(); displayStudents(); break;\n            case 7: performanceComparison(); break;\n            case 8: cout << "\\nProgram Ended Successfully.\\n"; break;\n            default: cout << "\\nInvalid Choice!\\n";\n        }\n    } while (choice != 8);\n    return 0;\n}', '2': '#include <iostream>\n#include <string>\n#include <vector>\n#include <cctype>\n#include <stdexcept>\nusing namespace std;\n\nstruct Node { char data; Node* next; };\nclass Stack {\n    Node* top = nullptr;\npublic:\n    Stack() = default;\n    Stack(const Stack&) = delete;\n    Stack& operator=(const Stack&) = delete;\n    ~Stack() { while (!isEmpty()) pop(); }\n    void push(char c) { top = new Node{c, top}; }\n    bool isEmpty() const { return top == nullptr; }\n    char peek() const { return isEmpty() ? \'\\0\' : top->data; }\n    char pop() {\n        if (isEmpty()) throw invalid_argument("Missing operand or parenthesis.");\n        Node* p = top; char c = p->data; top = p->next; delete p; return c;\n    }\n};\nint precedence(char c) {\n    if (c == \'^\') return 3;\n    if (c == \'*\' || c == \'/\') return 2;\n    if (c == \'+\' || c == \'-\') return 1;\n    return 0;\n}\nstring infixToPostfix(const string& infix) {\n    Stack ops; string out; bool operand = true;\n    for (unsigned char c : infix) {\n        if (isspace(c)) continue;\n        if (isalnum(c)) {\n            if (!operand) throw invalid_argument("Use single-character operands separated by operators.");\n            out += c; operand = false;\n        } else if (c == \'(\') {\n            if (!operand) throw invalid_argument("Missing operator before \'(\'.");\n            ops.push(c);\n        } else if (c == \')\') {\n            if (operand) throw invalid_argument("Missing operand before \')\'.");\n            while (!ops.isEmpty() && ops.peek() != \'(\') out += ops.pop();\n            if (ops.isEmpty()) throw invalid_argument("Unmatched \')\'.");\n            ops.pop();\n        } else if (precedence(c)) {\n            if (operand) throw invalid_argument("Missing operand; unary operators are unsupported.");\n            while (!ops.isEmpty() && ops.peek() != \'(\' &&\n                  (precedence(ops.peek()) > precedence(c) ||\n                  (precedence(ops.peek()) == precedence(c) && c != \'^\'))) out += ops.pop();\n            ops.push(c); operand = true;\n        } else throw invalid_argument("Invalid character in expression.");\n    }\n    if (operand) throw invalid_argument("Empty expression or missing final operand.");\n    while (!ops.isEmpty()) {\n        char c = ops.pop();\n        if (c == \'(\') throw invalid_argument("Unmatched \'(\'.");\n        out += c;\n    }\n    return out;\n}\nstring postfixToPrefix(const string& postfix) {\n    vector<string> terms;\n    for (unsigned char c : postfix) {\n        if (isalnum(c)) terms.push_back(string(1, c));\n        else {\n            string right = terms.back(); terms.pop_back();\n            string left = terms.back(); terms.pop_back();\n            terms.push_back(string(1, c) + left + right);\n        }\n    }\n    return terms.back();\n}\nint main() {\n    string infix;\n    cout << "Enter Infix Expression (e.g., A+B*C): ";\n    if (!getline(cin, infix)) { cout << "\\nInput ended.\\n"; return 0; }\n    try {\n        string postfix = infixToPostfix(infix);\n        cout << "Postfix Expression: " << postfix << endl;\n        cout << "Prefix Expression:  " << postfixToPrefix(postfix) << endl;\n    } catch (const invalid_argument& e) {\n        cerr << "Invalid expression: " << e.what() << endl; return 1;\n    } catch (const bad_alloc&) {\n        cerr << "Not enough memory. Try a shorter expression.\\n"; return 1;\n    }\n}\n', '3': '#include <stdio.h>\n#include <iostream>\n#include <sstream>\n#include <string>\n#include <cstdlib>\n\n// Recover from malformed numeric tokens; EOF ends a redirected session cleanly.\ntemplate<class T> void readValue(T& value) {\n    std::string token;\n    while (std::cin >> token) {\n        std::istringstream parser(token);\n        char extra;\n        if ((parser >> value) && !(parser >> extra)) return;\n        std::cout << "Invalid input. Enter a valid number: ";\n    }\n    std::cout << "\\nInput ended.\\n";\n    std::exit(0);\n}\n\n#define SIZE 5\n\nint queue[SIZE];\nint front = -1, rear = -1;\n\nvoid enqueue(int value) {\n    if ((rear + 1) % SIZE == front) {\n        printf("Circular Queue is Full!\\n");\n        return;\n    }\n    if (front == -1)\n        front = 0;\n    rear = (rear + 1) % SIZE;\n    queue[rear] = value;\n    printf("%d inserted into queue.\\n", value);\n}\n\nvoid dequeue() {\n    if (front == -1) {\n        printf("Circular Queue is Empty!\\n");\n        return;\n    }\n    printf("%d deleted from queue.\\n", queue[front]);\n    if (front == rear) {\n        front = -1;\n        rear = -1;\n    } else {\n        front = (front + 1) % SIZE;\n    }\n}\n\nvoid display() {\n    int i;\n    if (front == -1) {\n        printf("Circular Queue is Empty!\\n");\n        return;\n    }\n    printf("Circular Queue: ");\n    i = front;\n    while (1) {\n        printf("%d ", queue[i]);\n        if (i == rear)\n            break;\n        i = (i + 1) % SIZE;\n    }\n    printf("\\n");\n}\n\nint main() {\n    int choice, value;\n    while (1) {\n        printf("\\n--- CIRCULAR QUEUE ---\\n");\n        printf("1. Enqueue\\n");\n        printf("2. Dequeue\\n");\n        printf("3. Display\\n");\n        printf("4. Exit\\n");\n        printf("Enter your choice: ");\n        readValue(choice);\n        switch (choice) {\n            case 1:\n                printf("Enter value: ");\n                readValue(value);\n                enqueue(value);\n                break;\n            case 2:\n                dequeue();\n                break;\n            case 3:\n                display();\n                break;\n            case 4:\n                printf("Program Ended.\\n");\n                return 0;\n            default:\n                printf("Invalid choice!\\n");\n        }\n    }\n    return 0;\n}', '4': 'import math\n\ndef read_number(prompt, kind=int, minimum=None, strictly_positive=False):\n    while True:\n        try:\n            value = kind(input(prompt))\n            if not math.isfinite(value):\n                raise ValueError\n            if minimum is not None and value < minimum:\n                raise ValueError\n            if strictly_positive and value <= 0:\n                raise ValueError\n            return value\n        except (ValueError, OverflowError):\n            rule = " greater than zero" if strictly_positive else (\n                f" at least {minimum}" if minimum is not None else "")\n            print(f"Invalid input. Enter a valid {kind.__name__}{rule}.")\n\nclass Node:\n    def __init__(self, data):\n        self.data = data\n        self.left = None\n        self.right = None\n\ndef insert(root, data):\n    if root is None:\n        return Node(data)\n    node = root\n    while data != node.data:\n        side = \'left\' if data < node.data else \'right\'\n        child = getattr(node, side)\n        if child is None:\n            setattr(node, side, Node(data))\n            break\n        node = child\n    return root\n\ndef search(root, data):\n    while root is not None:\n        if data == root.data:\n            return True\n        root = root.left if data < root.data else root.right\n    return False\n\ndef delete(root, data):\n    parent, node = None, root\n    while node and node.data != data:\n        parent, node = node, node.left if data < node.data else node.right\n    if node is None:\n        return root\n    if node.left and node.right:\n        successor_parent, successor = node, node.right\n        while successor.left:\n            successor_parent, successor = successor, successor.left\n        node.data = successor.data\n        parent, node = successor_parent, successor\n    child = node.left if node.left else node.right\n    if parent is None:\n        return child\n    if parent.left is node:\n        parent.left = child\n    else:\n        parent.right = child\n    return root\n\ndef display(root, space=0):\n    stack = [(root, space, False)]\n    while stack:\n        node, depth, emit = stack.pop()\n        if node is None:\n            continue\n        if emit:\n            print(\' \' * (depth + 5) + str(node.data))\n        else:\n            stack.extend([(node.left, depth + 5, False),\n                          (node, depth, True), (node.right, depth + 5, False)])\n\ndef traverse(root, order):\n    stack = [(root, False)]\n    while stack:\n        node, emit = stack.pop()\n        if node is None:\n            continue\n        if emit:\n            print(node.data, end=\' \')\n        elif order == \'in\':\n            stack.extend([(node.right, False), (node, True), (node.left, False)])\n        elif order == \'pre\':\n            stack.extend([(node.right, False), (node.left, False), (node, True)])\n        else:\n            stack.extend([(node, True), (node.right, False), (node.left, False)])\n\ndef inorder(root):\n    traverse(root, \'in\')\n\ndef preorder(root):\n    traverse(root, \'pre\')\n\ndef postorder(root):\n    traverse(root, \'post\')\n\n\ndef main():\n    root = None\n    print("Create Binary Search Tree")\n\n    while True:\n        value = read_number("Enter value to insert: ")\n        root = insert(root, value)\n        choice = input("Do you want to insert another element? (y/n): ")\n        while choice.lower() not in (\'y\', \'n\'):\n            choice = input(\'Please enter y or n: \')\n        if choice.lower() == \'n\':\n            break\n\n    print("\\n========== BST ==========")\n    display(root)\n\n    print("\\nSearch Operation:")\n    search_val = read_number("Enter value to search: ")\n    if search(root, search_val):\n        print(f"{search_val} found in the BST")\n    else:\n        print(f"{search_val} not found in the BST")\n\n    print("\\nInorder Traversal:")\n    inorder(root)\n    print()\n\n    print("\\nPreorder Traversal:")\n    preorder(root)\n    print()\n\n    print("\\nPostorder Traversal:")\n    postorder(root)\n    print()\n\n    print("\\nDeletion Operation:")\n    del_val = read_number("Enter value to delete: ")\n    if search(root, del_val):\n        root = delete(root, del_val)\n        print(f"{del_val} deleted successfully")\n    else:\n        print(f"{del_val} not found in the BST")\n\n    print("\\nUpdated Inorder Traversal:")\n    inorder(root)\n    print()\n\nif __name__ == "__main__":\n    try:\n        main()\n    except (EOFError, KeyboardInterrupt):\n        print("\\nInput ended.")\n', '5': 'departments = ["Computer", "IT", "Mechanical", "Civil", "Electrical", "Library"]\nV = len(departments)\n\nedges = [\n    (0, 1, 10), (0, 2, 15), (0, 3, 20), (0, 5, 25),\n    (1, 2, 35), (1, 4, 30), (1, 5, 20), (2, 3, 40),\n    (2, 4, 25), (3, 4, 15), (3, 5, 30), (4, 5, 10)\n]\n\ndef create_adjacency_matrix():\n    matrix = [[0 for _ in range(V)] for _ in range(V)]\n    for u, v, weight in edges:\n        matrix[u][v] = weight\n        matrix[v][u] = weight\n    return matrix\n\ndef display_matrix():\n    matrix = create_adjacency_matrix()\n    print("\\nAdjacency Matrix:")\n    print() \n    print(f"{\'\':8}", end="")\n    for name in departments:\n        print(f"{name:8}", end="") \n    print()\n    for i in range(V):\n        print(f"{departments[i]:8}", end="")\n        for j in range(V):\n            print(f"{matrix[i][j]:>10}", end="") \n        print()\n\ndef find(parent, vertex):\n    if parent[vertex] != vertex: \n        parent[vertex] = find(parent, parent[vertex]) \n    return parent[vertex]\n\ndef union(parent, rank, u, v):\n    root_u = find(parent, u)\n    root_v = find(parent, v)\n    if root_u == root_v: \n        return False \n    if rank[root_u] < rank[root_v]:\n        parent[root_u] = root_v \n    elif rank[root_u] > rank[root_v]:\n        parent[root_v] = root_u \n    else:\n        parent[root_v] = root_u\n        rank[root_u] += 1 \n    return True\n\ndef kruskal():\n    if V == 0:\n        return [], 0\n    sorted_edges = sorted(edges, key=lambda x: x[2])\n    parent = [i for i in range(V)]\n    rank = [0] * V\n    mst = [] \n    total_distance = 0 \n    for u, v, weight in sorted_edges:\n        if union(parent, rank, u, v):\n            mst.append((u, v, weight))\n            total_distance += weight\n        if len(mst) == V - 1:\n            break \n    if len(mst) != V - 1:\n        raise ValueError("Graph is disconnected; no spanning tree exists.")\n    return mst, total_distance\n\ndef create_adjacency_list():\n    adjacency_list = [[] for _ in range(V)] \n    for u, v, weight in edges:\n        adjacency_list[u].append((v, weight))\n        adjacency_list[v].append((u, weight)) \n    return adjacency_list\n\ndef prim():\n    if V == 0:\n        return [], 0\n    adjacency_list = create_adjacency_list()\n    selected = [False] * V\n    mst = []\n    total_distance = 0\n    selected[0] = True \n    while len(mst) < V - 1:\n        minimum_weight = float("inf")\n        selected_u = -1\n        selected_v = -1\n        for u in range(V):\n            if selected[u]:\n                for v, weight in adjacency_list[u]:\n                    if not selected[v] and weight < minimum_weight:\n                        minimum_weight = weight\n                        selected_u = u\n                        selected_v = v\n        if selected_v == -1:\n            break\n        mst.append((selected_u, selected_v, minimum_weight)) \n        total_distance += minimum_weight\n        selected[selected_v] = True \n    if len(mst) != V - 1:\n        raise ValueError("Graph is disconnected; no spanning tree exists.")\n    return mst, total_distance \n\ndef display_mst(mst, total_distance, algorithm):\n    print("\\n" + "=" * 60)\n    print(algorithm)\n    print("=" * 60)\n    print(f"{\'From\':15}{\'To\':15}{\'Distance (m)\':15}")\n    print("-" * 45) \n    for u, v, weight in mst:\n        print(f"{departments[u]:15}{departments[v]:15}{weight:<15}") \n    print("-" * 45)\n    print("Total Minimum Distance =", total_distance, "meters")\n\n\ndef main():\n    print("=" * 60) \n    print(" COLLEGE CAMPUS MINIMUM SPANNING TREE") \n    print("=" * 60)\n    print("\\nDepartments / Institutes:")\n    for i in range(V):\n        print(i, "->", departments[i])\n\n    display_matrix()\n    kruskal_mst, kruskal_total = kruskal()\n    display_mst(kruskal_mst, kruskal_total, "KRUSKAL\'S ALGORITHM")\n\n    prim_mst, prim_total = prim()\n    display_mst(prim_mst, prim_total, "PRIM\'S ALGORITHM")\n\nif __name__ == "__main__":\n    try:\n        main()\n    except (EOFError, KeyboardInterrupt):\n        print("\\nInput ended.")\n', '6': 'def heapify_max(arr, n, i):\n    while True:\n        largest = i\n        left, right = 2 * i + 1, 2 * i + 2\n        if left < n and arr[left] > arr[largest]:\n            largest = left\n        if right < n and arr[right] > arr[largest]:\n            largest = right\n        if largest == i:\n            return\n        arr[i], arr[largest] = arr[largest], arr[i]\n        i = largest\n\ndef heapify_min(arr, n, i):\n    while True:\n        smallest = i\n        left, right = 2 * i + 1, 2 * i + 2\n        if left < n and arr[left] < arr[smallest]:\n            smallest = left\n        if right < n and arr[right] < arr[smallest]:\n            smallest = right\n        if smallest == i:\n            return\n        arr[i], arr[smallest] = arr[smallest], arr[i]\n        i = smallest\n\ndef max_heap_sort(arr):\n    n = len(arr)\n    for i in range(n // 2 - 1, -1, -1):\n        heapify_max(arr, n, i)\n    for i in range(n - 1, 0, -1):\n        arr[0], arr[i] = arr[i], arr[0]\n        heapify_max(arr, i, 0)\n\ndef min_heap_sort(arr):\n    n = len(arr)\n    for i in range(n // 2 - 1, -1, -1):\n        heapify_min(arr, n, i)\n    for i in range(n - 1, 0, -1):\n        arr[0], arr[i] = arr[i], arr[0]\n        heapify_min(arr, i, 0)\n\n\ndef main():\n    print("=" * 60)\n    print(" HEAP SORT ALGORITHM")\n    print("=" * 60)\n    print("\\n1. Max-Heap->Ascending Order")\n    print("2. Min-Heap->Descending Order")\n    choice = input("\\nEnter your choice (1 or 2):")\n    while choice not in (\'1\', \'2\'):\n        print("Invalid choice! Please select 1 or 2.")\n        choice = input("\\nEnter your choice (1 or 2):")\n    user_input = input("Enter integers separated by spaces:")\n    while True:\n        try:\n            arr = list(map(int, user_input.split()))\n            break\n        except ValueError:\n            print("Invalid input. Enter integers separated by spaces.")\n            user_input = input("Enter integers separated by spaces:")\n    print("\\nOriginal Array:", arr)\n\n    if choice == "1":\n        result = arr.copy()\n        max_heap_sort(result)\n        print("Heap Used: Max-Heap")\n        print("Sorted Array:", result)\n    elif choice == "2":\n        result = arr.copy()\n        min_heap_sort(result)\n        print("Heap Used: Min-Heap")\n        print("Sorted Array:", result)\n    else:\n        print("Invalid choice! Please select 1 or 2.")\n\n    print("\\nTime Complexity: O(nlogn)")\n    print("Space Complexity : O(1) auxiliary space")\n    print("+" * 60)\n\nif __name__ == "__main__":\n    try:\n        main()\n    except (EOFError, KeyboardInterrupt):\n        print("\\nInput ended.")\n', '7': 'import math\n\ndef read_number(prompt, kind=int, minimum=None, strictly_positive=False):\n    while True:\n        try:\n            value = kind(input(prompt))\n            if not math.isfinite(value):\n                raise ValueError\n            if minimum is not None and value < minimum:\n                raise ValueError\n            if strictly_positive and value <= 0:\n                raise ValueError\n            return value\n        except (ValueError, OverflowError):\n            rule = " greater than zero" if strictly_positive else (\n                f" at least {minimum}" if minimum is not None else "")\n            print(f"Invalid input. Enter a valid {kind.__name__}{rule}.")\n\ndef merge(orders, left, middle, right):\n    left_part = orders[left:middle + 1]\n    right_part = orders[middle + 1:right + 1]\n    i = 0\n    j = 0\n    k = left\n    while i < len(left_part) and j < len(right_part):\n        if left_part[i] <= right_part[j]:\n            orders[k] = left_part[i]\n            i = i + 1\n        else:\n            orders[k] = right_part[j]\n            j = j + 1\n        k = k + 1\n    while i < len(left_part):\n        orders[k] = left_part[i]\n        i = i + 1\n        k = k + 1\n    while j < len(right_part):\n        orders[k] = right_part[j]\n        j = j + 1\n        k = k + 1\n\ndef merge_sort(orders, left, right):\n    if left < right:\n        middle = (left + right) // 2\n        merge_sort(orders, left, middle)\n        merge_sort(orders, middle + 1, right)\n        merge(orders, left, middle, right)\n\ndef display_orders(orders):\n    if len(orders) == 0:\n        print("\\nNO orders available.")\n        return\n    print("\\n-------------------")\n    print(" ONLINE ORDERS ")\n    print("----------------------")\n    for i in range(len(orders)):\n        print("Order", i + 1, "->", orders[i], "minutes")\n    print("--------------------------")\n\ndef display_priority(orders):\n    if len(orders) == 0:\n        print("\\nNo orders available.")\n        return\n    print("\\n============================")\n    print(" DELIVERY PRIORITY")\n    print("=============================")\n    for i in range(len(orders)):\n        if i == 0:\n            print("Priority", i + 1, "->", orders[i], "minutes [HIGHEST]")\n        else:\n            print("Priority", i + 1, "->", orders[i], "minutes")\n    print("==================================================")\n\n\ndef main():\n    orders = []\n    while True:\n        print("\\n============================================")\n        print("ONLINE ORDER DELIVERY SYSTEM Using MERGE SORT")\n        print("============================================")\n        print("1.Add Orders")\n        print("2.Display Orders")\n        print("3.Sort Orders by Delivery Time")\n        print("4.Display Delivery Priority")\n        print("5.Exit")\n        print("=================================")\n        choice = read_number("Enter your choice:")\n        \n        if choice == 1:\n            number_of_orders = read_number("\\nEnter number of online orders:", minimum=0)\n            new_orders = []\n            print("\\nEnter estimated delivery time:")\n            for i in range(number_of_orders):\n                delivery_time = read_number("Order" + str(i + 1) + "(minutes):", minimum=0)\n                new_orders.append(delivery_time)\n            orders = new_orders\n            print("\\nOrders added successfully.")\n        elif choice == 2:\n            display_orders(orders)\n        elif choice == 3:\n            if len(orders) == 0:\n                print("\\nPlease add orders first.")\n            else:\n                print("\\nBefore Sorting.")\n                print(orders)\n                merge_sort(orders, 0, len(orders) - 1)\n                print("\\nAfter Sorting:")\n                print(orders)\n                print("\\nOrders sorted successfully.")\n        elif choice == 4:\n            if len(orders) == 0:\n                print("\\nPlease add orders first.")\n            else:\n                merge_sort(orders, 0, len(orders) - 1)\n                display_priority(orders)\n        elif choice == 5:\n            print("\\nThank you for using the system.")\n            break\n        else:\n            print("\\nInvalid choice.")\n            print("Please select a number from 1 to 5.")\n\nif __name__ == "__main__":\n    try:\n        main()\n    except (EOFError, KeyboardInterrupt):\n        print("\\nInput ended.")\n', '8': 'import math\n\ndef read_number(prompt, kind=int, minimum=None, strictly_positive=False):\n    while True:\n        try:\n            value = kind(input(prompt))\n            if not math.isfinite(value):\n                raise ValueError\n            if minimum is not None and value < minimum:\n                raise ValueError\n            if strictly_positive and value <= 0:\n                raise ValueError\n            return value\n        except (ValueError, OverflowError):\n            rule = " greater than zero" if strictly_positive else (\n                f" at least {minimum}" if minimum is not None else "")\n            print(f"Invalid input. Enter a valid {kind.__name__}{rule}.")\n\ndef fractional_knapsack(weights, profits, capacity):\n    if len(weights) != len(profits):\n        raise ValueError("Each weight needs one profit.")\n    if not math.isfinite(capacity) or capacity < 0:\n        raise ValueError("Capacity must be finite and nonnegative.")\n    if any(not math.isfinite(w) or w <= 0 for w in weights):\n        raise ValueError("Weights must be finite and greater than zero.")\n    if any(not math.isfinite(p) or p < 0 for p in profits):\n        raise ValueError("Profits must be finite and nonnegative.")\n    n = len(weights)\n    items = []\n    for i in range(n):\n        ratio = profits[i] / weights[i]\n        items.append([i + 1, weights[i], profits[i], ratio])\n        \n    items.sort(key=lambda x: x[3], reverse=True)\n    total_profit = 0\n    remaining_capacity = capacity\n    \n    print("\\nItems Selected:")\n    print("-" * 65)\n    print("Item\\tWeight\\tProfit\\tRatio\\tFraction\\tProfit Earned")\n    print("-" * 65)\n    \n    for item in items:\n        if remaining_capacity <= 0:\n            break\n        item_no = item[0]\n        weight = item[1]\n        profit = item[2]\n        ratio = item[3]\n        \n        if weight <= remaining_capacity:\n            fraction = 1\n            earned_profit = profit\n            taken_weight = weight\n        else:\n            fraction = remaining_capacity / weight\n            taken_weight = remaining_capacity\n            earned_profit = profit * fraction\n            \n        total_profit += earned_profit\n        remaining_capacity -= taken_weight\n        \n        print(f"{item_no}\\t{weight:.2f}\\t{profit:.2f}\\t{ratio:.2f}\\t{fraction * 100:.2f}%\\t\\t{earned_profit:.2f}")\n        \n        if remaining_capacity == 0:\n            break\n            \n    return total_profit\n\n\ndef main():\n    print("=" * 65)\n    print("FRACTIONAL KNAPSACK - SHIPPING COMPANY")\n    print("=" * 65)\n\n    n = read_number("\\nEnter number of parcels: ", minimum=0)\n    weights = []\n    profits = []\n\n    for i in range(n):\n        print(f"\\nParcel {i+1}")\n        weight = read_number("Enter weight: ", float, strictly_positive=True)\n        profit = read_number("Enter profit: ", float, minimum=0)\n        weights.append(weight)\n        profits.append(profit)\n\n    capacity = read_number("\\nEnter truck capacity: ", float, minimum=0)\n    maximum_profit = fractional_knapsack(weights, profits, capacity)\n\n    print("\\n" + "=" * 65)\n    print("FINAL RESULT")\n    print("=" * 65)\n    print(f"Truck Capacity: {capacity:.2f}")\n    print(f"Maximum Profit: {maximum_profit:.2f}")\n    print("=" * 65)\n\nif __name__ == "__main__":\n    try:\n        main()\n    except (EOFError, KeyboardInterrupt):\n        print("\\nInput ended.")\n', '9': 'def naive_string_matching(text, pattern):\n    n = len(text)\n    m = len(pattern)\n    indices = []\n    \n    if m == 0:\n        return list(range(n + 1))\n        \n    for i in range(n - m + 1):\n        match = True\n        for j in range(m):\n            if text[i + j] != pattern[j]:\n                match = False\n                break\n        if match:\n            indices.append(i)\n            \n    return indices\n\n\ndef main():\n\n    text = input("Enter the text string: ")\n    pattern = input("Enter the pattern string: ")\n    print("Text entered:", repr(text))\n    print("Pattern entered:", repr(pattern))\n\n    matches = naive_string_matching(text, pattern)\n\n    if matches:\n        print("Pattern found at starting indices (0-based):", matches)\n        print("Total number of matches:", len(matches))\n    else:\n        print("Pattern not found in the text.")\n\nif __name__ == "__main__":\n    try:\n        main()\n    except (EOFError, KeyboardInterrupt):\n        print("\\nInput ended.")\n', '10': 'import numpy as np\nimport heapq\nfrom collections import deque\n\ndef generate_maze_static():\n    """Returns a fixed static maze (0 = free, 1 = wall)."""\n    return np.array([\n        [0, 1, 0, 0, 0, 0],\n        [0, 1, 0, 1, 1, 0],\n        [0, 0, 0, 1, 0, 0],\n        [0, 1, 1, 0, 0, 1],\n        [0, 0, 0, 0, 1, 0],\n        [1, 1, 0, 1, 0, 0]\n    ])\n\ndef generate_maze_dynamic(size=10, p_open=0.7):\n    """Generates a random dynamic maze of given size."""\n    if not isinstance(size, int) or size <= 0:\n        raise ValueError("Maze size must be a positive integer.")\n    if not np.isfinite(p_open) or not 0 <= p_open <= 1:\n        raise ValueError("Open-cell probability must be between 0 and 1.")\n    maze = np.random.choice(\n        [0, 1], (size, size), p=[p_open, 1 - p_open]\n    )\n    maze[0, 0] = 0\n    maze[-1, -1] = 0\n    return maze\n\ndef neighbors(maze, node):\n    """Returns neighboring free cells of the current node."""\n    x, y = node\n    nbs = []\n    for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:\n        nx, ny = x + dx, y + dy\n        if (0 <= nx < maze.shape[0] and 0 <= ny < maze.shape[1] and maze[nx, ny] == 0):\n            nbs.append((nx, ny))\n    return nbs\n\ndef heuristic(a, b):\n    """Manhattan distance heuristic."""\n    return abs(a[0] - b[0]) + abs(a[1] - b[1])\n\ndef reconstruct_path(parent, goal):\n    """Reconstructs the path from start to goal."""\n    path = []\n    node = goal\n    while node is not None:\n        path.append(node)\n        node = parent.get(node)\n    path.reverse()\n    return path\n\ndef valid_endpoints(maze, start, goal):\n    if maze.ndim != 2 or not maze.size:\n        return False\n    return all(len(p) == 2 and all(isinstance(x, (int, np.integer)) for x in p)\n               and 0 <= p[0] < maze.shape[0] and 0 <= p[1] < maze.shape[1]\n               and maze[p] == 0 for p in (start, goal))\n\ndef bfs(maze, start, goal):\n    """Breadth-First Search."""\n    if not valid_endpoints(maze, start, goal):\n        return [], []\n    queue = deque([start])\n    visited = {start}\n    parent = {start: None}\n    explored = []\n    \n    while queue:\n        node = queue.popleft()\n        explored.append(node)\n        if node == goal:\n            return reconstruct_path(parent, goal), explored\n        for nb in neighbors(maze, node):\n            if nb not in visited:\n                visited.add(nb)\n                parent[nb] = node\n                queue.append(nb)\n                \n    return [], explored\n\ndef dfs(maze, start, goal):\n    """Depth-First Search."""\n    if not valid_endpoints(maze, start, goal):\n        return [], []\n    stack = [start]\n    visited = {start}\n    parent = {start: None}\n    explored = []\n    \n    while stack:\n        node = stack.pop()\n        explored.append(node)\n        if node == goal:\n            return reconstruct_path(parent, goal), explored\n        for nb in neighbors(maze, node):\n            if nb not in visited:\n                visited.add(nb)\n                parent[nb] = node\n                stack.append(nb)\n                \n    return [], explored\n\ndef astar(maze, start, goal):\n    """A* Search using Manhattan distance."""\n    if not valid_endpoints(maze, start, goal):\n        return [], []\n    open_set = [(heuristic(start, goal), 0, start)]\n    heapq.heapify(open_set)\n    g_score = {start: 0}\n    parent = {start: None}\n    visited = set()\n    explored = []\n    \n    while open_set:\n        _, cost, current = heapq.heappop(open_set)\n        if current in visited:\n            continue\n        visited.add(current)\n        explored.append(current)\n        if current == goal:\n            return reconstruct_path(parent, goal), explored\n        for nb in neighbors(maze, current):\n            temp_g = cost + 1\n            if temp_g < g_score.get(nb, float("inf")):\n                g_score[nb] = temp_g\n                parent[nb] = current\n                f_score = temp_g + heuristic(nb, goal)\n                heapq.heappush(open_set, (f_score, temp_g, nb))\n                \n    return [], explored\n\ndef display_maze(maze, path, explored, start, goal, title):\n    """Displays the maze, explored cells, and final path."""\n    import matplotlib.pyplot as plt\n    display = np.zeros((*maze.shape, 3))\n    \n    # Free cells are white; walls are black.\n    display[maze == 0] = [1, 1, 1]\n    display[maze == 1] = [0, 0, 0]\n    \n    # Explored cells are light blue.\n    for x, y in explored:\n        display[x, y] = [0.6, 0.8, 1]\n        \n    # Final path is green.\n    for x, y in path:\n        display[x, y] = [0, 0.8, 0]\n        \n    # Start is blue; goal is red.\n    display[start] = [0, 0, 1]\n    display[goal] = [1, 0, 0]\n    \n    plt.figure(figsize=(6, 6))\n    plt.imshow(display)\n    plt.title(title)\n    plt.xticks(range(maze.shape[1]))\n    plt.yticks(range(maze.shape[0]))\n    plt.grid(True, color="gray", linewidth=0.5)\n    plt.show()\n\ndef main():\n    maze = generate_maze_static()\n    start = (0, 0)\n    goal = (5, 5)\n    algorithms = [\n        ("BFS", bfs),\n        ("DFS", dfs),\n        ("A*", astar)\n    ]\n    \n    for name, algorithm in algorithms:\n        path, explored = algorithm(maze, start, goal)\n        print(f"\\n{name} Algorithm")\n        print("Path:", path if path else "No path found")\n        print("Path length:", len(path) - 1 if path else 0)\n        print("Nodes explored:", len(explored))\n        if \'--no-gui\' not in __import__(\'sys\').argv:\n            display_maze(maze, path, explored, start, goal, name)\n\nif __name__ == "__main__":\n    main()'}
GUIDES = {1: {'aim': 'Maintain student records and demonstrate searching and sorting.', 'theory': 'A linear search scans records in order. Binary search halves a sorted ID range. Bubble sort exchanges adjacent out-of-order names; selection sort repeatedly chooses the highest remaining CGPA.', 'algorithm': '1. Add validated student records to a dynamic vector.\n2. Display records or search by ID.\n3. For binary search, first bubble-sort records by ID.\n4. Sort names ascending or CGPA descending when selected.\n5. Repeat the menu until Exit or EOF.', 'sample': 'Choose 1; add 3 students: (30, Zed, 7), (10, Amy, 9), (20, Bob, 8).\nChoose 3 and search 20. Choose 4 and search 30. Choose 5, then 6, then 8.', 'output': 'Linear search for 20: Student Found; Comparisons: 3.\nBinary search for 30: Student Found; Comparisons: 2.\nName order: Amy, Bob, Zed. Descending CGPA: Amy(9), Bob(8), Zed(7).', 'complexity': 'Linear search O(n); binary-search loop O(log n); all three demonstration sorts O(n^2). Binary-search menu operation includes O(n^2) presorting. Records use O(n) space.', 'explanation': 'Student holds ID, a single-token name, and CGPA. readValue validates an entire numeric token and exits on EOF. addStudent bounds the count and uses vector storage. Search functions count inspected records. Name and CGPA sorts move complete Student records, preserving their fields.', 'edges': 'No records: report No Records Found. Negative/zero additions are rejected; total is capped at 100000. Names may exceed 29 characters safely but still contain no spaces. CGPA uses the assumed 0-10 scale. Repeated IDs are allowed, and a search returns one matching record.', 'viva': 'Q: Why sort before binary search?\nA: Its half-selection rule requires ordered keys.\nQ: Is this whole binary-search operation O(log n)?\nA: No; the included bubble sort makes it O(n^2).\nQ: Why vector and string?\nA: They manage storage and remove the unsafe fixed name buffer/realloc pattern.', 'fixes': 'Replaced unsafe realloc/fixed name buffers; validated counts and numeric input; handled EOF/allocation failure; clarified binary-search presorting cost.'}, 2: {'aim': 'Convert a valid infix expression into postfix and prefix using stacks.', 'theory': 'Infix places an operator between operands. Postfix places it after them; prefix places it before them. A stack enforces precedence and associativity. ^ is right-associative; +, -, *, / are left-associative.', 'algorithm': '1. Scan the infix expression, skipping spaces.\n2. Output operands and stack operators/parentheses.\n3. Pop higher-precedence operators, and equal-precedence left-associative operators.\n4. Reject malformed syntax and drain the operator stack.\n5. Scan postfix; push operands and combine each operator with its left and right terms to form prefix.', 'sample': 'Enter Infix Expression (e.g., A+B*C): A-B-C', 'output': 'Postfix Expression: AB-C-\nPrefix Expression:  --ABC\nFor A^B^C: postfix ABC^^; prefix ^A^BC.', 'complexity': 'Postfix conversion O(n) time and O(n) space. Prefix construction uses string concatenation and can take O(n^2) time for skewed expressions; its stored terms use O(n) space.', 'explanation': 'Stack is a linked list whose destructor releases remaining nodes. precedence assigns operator priorities. infixToPostfix tracks whether an operand is expected and checks parentheses. postfixToPrefix pops right first, then left, because the last pushed term is the right operand.', 'edges': 'Only single-character alphanumeric operands and binary + - * / ^ are supported. AB, unary -A, empty input, missing operators, invalid characters, and unmatched parentheses are rejected. Long expressions use strings rather than 100-character buffers.', 'viva': 'Q: Why does A^B^C mean A^(B^C)?\nA: Exponentiation is right-associative here.\nQ: Why pop right before left when converting postfix?\nA: The right term was pushed most recently.\nQ: Does postfix need parentheses?\nA: No; operand/operator order encodes grouping.', 'fixes': 'Corrected prefix associativity, removed fixed-buffer truncation, validated the expression grammar, and released linked stack nodes.'}, 3: {'aim': 'Implement a five-element circular queue with enqueue, dequeue, and display.', 'theory': 'A queue is FIFO. Circular indexing reuses slots freed at the front. Here front=rear=-1 represents empty; (rear+1)%SIZE==front represents full.', 'algorithm': '1. Initialize front and rear to -1.\n2. Enqueue: reject full; set front for the first item; advance rear modulo SIZE and store.\n3. Dequeue: reject empty; remove front; reset both indices after the last item or advance front modulo SIZE.\n4. Display from front to rear using circular advancement.', 'sample': 'Enqueue 1,2,3,4,5; try enqueue 6; dequeue once; enqueue 7; display; dequeue until empty.', 'output': 'Enqueue 6: Circular Queue is Full!\nAfter wraparound: Circular Queue: 2 3 4 5 7\nDequeue from empty: Circular Queue is Empty!', 'complexity': 'Enqueue/dequeue O(1); display O(k) for k stored items; O(SIZE) storage. All five slots are usable.', 'explanation': 'queue stores values. front points to the oldest value and rear to the newest. Modulo SIZE wraps the index. The single-item dequeue branch is essential to restore the empty sentinel state. readValue recovers from malformed numeric tokens.', 'edges': 'Test empty/full queues, wraparound after deletion, deleting the last item, negative values, invalid menu choices, malformed numbers, and EOF. Negative queue values are valid data.', 'viva': 'Q: Why use modulo?\nA: To wrap an index back to the first slot.\nQ: Is one slot deliberately unused?\nA: No; the separate -1 empty state allows all SIZE slots.\nQ: Which order is removed?\nA: First in, first out.', 'fixes': 'Preserved correct queue logic; replaced unchecked scanf input with validated numeric reads and clean EOF handling.'}, 4: {'aim': 'Create a BST and demonstrate search, traversals, display, and deletion.', 'theory': 'Each BST node has smaller keys in its left subtree and larger keys in its right subtree. Inorder traversal yields sorted keys. Duplicate insertion is ignored in this implementation.', 'algorithm': '1. Insert each key by following left/right comparisons.\n2. Search by following the same comparisons.\n3. Traverse in inorder, preorder, or postorder using explicit stacks.\n4. Delete a leaf or one-child node by relinking its parent.\n5. For two children, replace its value with the inorder successor and remove that successor.', 'sample': 'Insert 5,3,7,2,4,6,8 (answer y after each except the last). Search 6. Delete 5.', 'output': '6 found in the BST\nInorder: 2 3 4 5 6 7 8\nPreorder: 5 3 2 4 7 6 8\nPostorder: 2 4 3 6 8 7 5\nAfter deleting 5: 2 3 4 6 7 8', 'complexity': 'Insert/search/delete O(h), where h is tree height: O(log n) for a balanced shape, O(n) for a chain. Traversals O(n) time and O(h) stack space. The indented display also costs time proportional to printed spacing.', 'explanation': 'Node stores data and two child references. Iterative insert/search follow a single branch. delete tracks parent links and handles the successor case. traverse uses a stack of (node, emit) entries to control visit order without recursive calls.', 'edges': 'Duplicate insertion, missing search/delete, root deletion, leaf deletion, one/two children, empty tree operations, a deep chain, malformed integers, invalid y/n input, and EOF are covered.', 'viva': 'Q: Why does inorder sort the keys?\nA: It visits smaller subtree, node, then larger subtree.\nQ: Why use an inorder successor?\nA: It is the smallest larger key and preserves the BST ordering.\nQ: Does iterative code balance the tree?\nA: No; it avoids recursion-limit failures but a skewed tree is still slow.', 'fixes': 'Replaced recursive operations with iterative versions; added input recovery and correct missing-deletion messages.'}, 5: {'aim': 'Find a minimum cable-distance spanning tree for six campus departments with Kruskal and Prim.', 'theory': 'An MST connects every vertex with V-1 edges, no cycles, and minimum total weight. Kruskal grows a forest from globally lightest edges. Prim grows one connected tree using the lightest edge leaving it.', 'algorithm': 'Kruskal: sort edges; use disjoint-set find/union to skip cycles; stop after V-1 accepted edges.\nPrim: start at vertex 0; repeatedly scan outgoing edges of selected vertices and choose the lightest edge to an unselected vertex.\nReject a disconnected graph when a complete spanning tree cannot be formed.', 'sample': 'No keyboard input. Run the fixed six-department campus graph.', 'output': "Both KRUSKAL'S ALGORITHM and PRIM'S ALGORITHM produce 5 edges.\nTotal Minimum Distance = 70 meters\nOne MST: Computer-IT 10; Electrical-Library 10; Computer-Mechanical 15; Civil-Electrical 15; IT-Library 20.", 'complexity': 'Kruskal is dominated by O(E log E) sorting. This simple scan-based Prim implementation costs O(VE), rather than heap-based O(E log V). The adjacency matrix needs O(V^2) space.', 'explanation': 'departments maps vertex indices to names. edges holds undirected weighted edges. find compresses paths; union uses rank. kruskal prevents cycles with the disjoint set. prim tracks selected vertices and scans candidate edges. The two display functions show the graph and resulting trees.', 'edges': 'The fixed graph is connected. Disconnected graphs raise a clear error instead of labeling a partial forest an MST. Empty graphs return an empty tree with distance 0. Equal-weight choices may produce different correct MSTs with the same total.', 'viva': 'Q: How many edges are in an MST?\nA: V-1 for a nonempty connected graph.\nQ: Why use union-find?\nA: To detect whether an edge would close a cycle.\nQ: Is the MST always unique?\nA: No; tied weights can allow several optimal trees.', 'fixes': 'Preserved fixed-graph results; detected disconnected graphs and handled the empty graph; guarded the demonstration for safe imports.'}, 6: {'aim': 'Sort integers using a max heap for ascending order or a min heap for descending order.', 'theory': 'A max heap keeps each parent at least as large as its children. Moving the root to the final unsorted position repeatedly produces ascending order. A min heap gives descending order by the same process.', 'algorithm': '1. Read the sort choice and integer array.\n2. Heapify internal nodes bottom-up.\n3. Swap the root with the last unsorted element.\n4. Shrink the active heap and restore its property.\n5. Repeat until one element remains.', 'sample': 'Choose 1; enter: 3 -1 3 0\nChoose 2 on a second run with the same array.', 'output': 'Choice 1: Sorted Array: [-1, 0, 3, 3]\nChoice 2: Sorted Array: [3, 3, 0, -1]', 'complexity': 'O(n) heap construction and O(n log n) total time; O(1) auxiliary space for the in-place sorting functions. The demonstration additionally copies the input into result, using O(n) storage.', 'explanation': 'heapify_max/min repeatedly compare a node with children at 2*i+1 and 2*i+2 and move it down. max_heap_sort/min_heap_sort first build the heap, then extract the extreme element into its final array position.', 'edges': 'Empty input is an empty array; singleton, duplicates, negative integers, sorted/reverse arrays, invalid choices, malformed tokens, and EOF are handled. The UI retries the whole array after a bad token.', 'viva': 'Q: Why start building at n//2-1?\nA: Later indices are leaves and already valid one-node heaps.\nQ: Is heap sort stable?\nA: Generally no.\nQ: Why iterative heapify?\nA: It avoids recursion stack space and makes in-place auxiliary space O(1).', 'fixes': 'Validated menu/array input and handled EOF; made heapify iterative to support the stated in-place auxiliary-space claim.'}, 7: {'aim': 'Sort estimated delivery times and display delivery priority using merge sort.', 'theory': 'Merge sort divides an array into halves and merges sorted halves. Choosing the left item on equal values makes the merge stable. Shortest estimated delivery time is given highest priority here.', 'algorithm': '1. Add a complete nonnegative batch of delivery times.\n2. Recursively split the array until subarrays have at most one item.\n3. Merge adjacent sorted halves using temporary lists.\n4. Display ascending times or rank them by priority.\n5. Repeat until Exit.', 'sample': 'Choose 1; number of orders 3; times 20,10,20. Choose 3, then 4, then 5.', 'output': 'After Sorting: [10, 20, 20]\nPriority 1 -> 10 minutes [HIGHEST]\nPriority 2 -> 20 minutes\nPriority 3 -> 20 minutes', 'complexity': 'O(n log n) sorting time, O(n) auxiliary storage plus O(log n) recursion depth. Sorting an empty or singleton list terminates immediately.', 'explanation': 'merge copies left/right slices and writes back the smaller next value. merge_sort splits at the middle. The menu keeps orders; a newly entered batch replaces the old batch only when fully read. Priority display sorts first, then labels the first item highest.', 'edges': 'Zero orders, duplicate times, zero-minute estimates, attempts to display/sort before adding, bad integers, negative counts/times, and EOF are handled. Adding orders replaces the previous batch, matching the original behavior.', 'viva': 'Q: What makes the merge stable?\nA: Taking the left item first when values are equal.\nQ: Why O(n log n)?\nA: There are log n division levels, each merging n values in total.\nQ: Is this in-place?\nA: No; it creates temporary lists.', 'fixes': 'Added numeric/domain validation and EOF handling; avoided replacing the previous batch before all new data is read.'}, 8: {'aim': 'Maximize shipping profit with a fractional knapsack capacity constraint.', 'theory': 'When parcels are divisible, choosing descending profit/weight ratio is optimal. Take full parcels while possible, then the fraction of the next parcel that fills the remaining capacity. This does not solve the indivisible 0/1 knapsack problem.', 'algorithm': '1. Validate positive weights, nonnegative profits, and capacity.\n2. Compute each profit/weight ratio.\n3. Sort parcels by descending ratio.\n4. Take each whole parcel or the fitting fraction.\n5. Sum earned profit and stop when capacity is exhausted.', 'sample': '3 parcels: weights 10,20,30; matching profits 60,100,120; truck capacity 50.\nEnter each parcel weight then its profit, as prompted.', 'output': 'Select parcel 1 fully (profit 60), parcel 2 fully (profit 100), and 66.67% of parcel 3 (profit 80).\nMaximum Profit: 240.00', 'complexity': 'O(n log n) sorting time and O(n) extra storage for sorted item records.', 'explanation': 'Each item records its original number, weight, profit, and ratio. The greedy loop computes fraction=min(1, remaining/weight), adds its earned profit, and subtracts the taken weight. The table prints original parcel size/profit plus the fraction actually selected.', 'edges': 'Zero weights are rejected to prevent division by zero. Negative weights/profits/capacity, NaN/inf, and mismatched function argument lists are rejected. Zero capacity or zero parcels gives profit 0. Input failures reprompt; EOF ends cleanly.', 'viva': 'Q: Why use profit/weight instead of profit alone?\nA: It measures value per capacity unit.\nQ: Can a parcel be split?\nA: Yes; that is the fractional assumption.\nQ: Does this greedy rule solve 0/1 knapsack?\nA: No; indivisible choices require a different approach.', 'fixes': 'Validated all numeric domains and matching lists; prevented zero-weight division and misleading zero-capacity selection rows.'}, 9: {'aim': 'Find every occurrence of a pattern in a text with naive string matching.', 'theory': 'Align the pattern at each possible text index and compare characters left to right. A failed comparison rejects that alignment; a full match records its zero-based start index.', 'algorithm': '1. Read text and pattern as complete lines.\n2. If the pattern is empty, return every boundary index 0 through n.\n3. For each alignment 0 through n-m, compare all m characters.\n4. Record matches and print their indices and count.', 'sample': 'Enter the text string: ababa\nEnter the pattern string: aba', 'output': 'Pattern found at starting indices (0-based): [0, 2]\nTotal number of matches: 2', 'complexity': 'Worst-case O((n-m+1)*m) time for 0<m<=n; O(k) output space for k matches. Empty pattern returns n+1 indices.', 'explanation': 'naive_string_matching checks every legal starting index without skipping overlapping matches. The inner loop stops at the first mismatch. repr in the main routine makes spaces and empty strings visible in the echoed input.', 'edges': 'Overlaps are included. Matching is case-sensitive. Spaces are ordinary characters. Empty pattern matches all text boundaries; a longer pattern gives no matches. EOF/interrupt is handled.', 'viva': 'Q: Are indices zero-based?\nA: Yes.\nQ: Why does aa occur three times in aaaa?\nA: Alignments 0, 1, and 2 overlap and all match.\nQ: How does KMP differ?\nA: It uses pattern-prefix information to avoid repeated comparisons.', 'fixes': 'The matching logic was already correct; added clean EOF/interrupt handling.'}, 10: {'aim': 'Compare BFS, DFS, and A* pathfinding on a maze and visualize exploration.', 'theory': 'Maze cells form a graph with four-direction moves and unit edge cost. BFS finds a shortest path; DFS finds a reachable path without shortest-path guarantees. A* prioritizes g+h using Manhattan distance, which is admissible and consistent for this movement model.', 'algorithm': '1. Load the fixed maze and validate free, in-bounds endpoints.\n2. Use a queue for BFS, a stack for DFS, or a heap of g+h scores for A*.\n3. Record parents and explored cells.\n4. On reaching the goal, reconstruct the parent chain.\n5. Print path/length/explored count and display each algorithm plot.', 'sample': 'No keyboard input. Close each plot window to continue.\nUse --no-gui for text only; NumPy is still required.', 'output': 'For the supplied static maze, all three algorithms report:\nPath: No path found\nPath length: 0\nThe goal (5,5) is disconnected from start (0,0). Explored counts depend on the algorithm.', 'complexity': 'BFS/DFS O(V+E) time and O(V) storage. Heap-based A* is typically O((V+E) log V) here. On a four-neighbor grid E=O(V).', 'explanation': 'neighbors filters wall and boundary cells. bfs/dfs track visited cells at discovery. astar maintains best g scores and a priority heap. reconstruct_path follows parent links back to start. display_maze colors walls black, explored cells light blue, path green, start blue, and goal red.', 'edges': 'Blocked/out-of-range endpoints return no path. Start equal to a free goal gives a one-cell path and zero steps. Random mazes may have no solution. Invalid maze sizes/probabilities are rejected. Desktop plots require a usable display/backend.', 'viva': 'Q: Which algorithm guarantees the fewest steps here?\nA: BFS and A* with this consistent heuristic.\nQ: Why Manhattan distance?\nA: Moves are horizontal/vertical and cost one.\nQ: Why no path in the fixed maze?\nA: Its goal component is disconnected; that result is not an algorithm error.', 'fixes': 'Validated endpoints and dynamic-maze parameters; made plotting imports lazy and added text-only --no-gui mode.'}}
TITLES = ['Student database', 'Infix / postfix / prefix', 'Circular queue',
          'Binary search tree', 'Minimum spanning tree', 'Heap sort',
          'Merge sort / delivery orders', 'Fractional knapsack',
          'Naive string matching', 'Maze BFS / DFS / A*']

def command_text(argv):
    return subprocess.list2cmdline(list(map(str, argv))) if sys.platform == 'win32' else shlex.join(list(map(str, argv)))

def windows_host():
    return sys.platform == 'win32'

def compiler_help():
    if windows_host():
        print('Windows C++ needs Microsoft Visual C++ Build Tools (Desktop development with C++ and Windows SDK).\nInstall/repair that workload in Visual Studio Installer, then reopen the launcher.\nAn existing x64 Native Tools Command Prompt is also supported. MinGW is deliberately not used.')
    else:
        print('Missing C++ compiler.\nRun: sudo apt install build-essential\nThen select the practical again.')

def find_compiler():
    """Return (compiler, environment); never launch MinGW on Windows."""
    if not windows_host():
        return shutil.which('g++'), None
    compiler = shutil.which('cl.exe')
    if compiler and os.environ.get('INCLUDE') and os.environ.get('LIB'):
        return compiler, None
    base = Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)'))
    vswhere = base/'Microsoft Visual Studio'/'Installer'/'vswhere.exe'
    if not vswhere.is_file():
        return None, None
    found = execute([vswhere, '-latest', '-products', '*', '-requires',
                     'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath'], 'setup', True)
    if found is None or not found.stdout.strip():
        return None, None
    developer = Path(found.stdout.strip())/'Common7'/'Tools'/'VsDevCmd.bat'
    if not developer.is_file():
        return None, None
    # This installed-tool path is passed to cmd, so reject shell expansion chars.
    if any(char in str(developer) for char in '%!&|<>^"\r\n'):
        print('Use the x64 Native Tools Command Prompt for this unusual Visual Studio installation path.')
        return None, None
    cmd = os.environ.get('COMSPEC', 'cmd.exe')
    setup = f'"{cmd}" /d /s /c "call "{developer}" -no_logo -arch=x64 -host_arch=x64 && set"'
    print('$ ' + setup, flush=True)
    try:
        result = subprocess.run(setup, capture_output=True, text=True, errors='replace', timeout=60)
    except (OSError, subprocess.TimeoutExpired) as exc:
        print('Visual C++ environment setup failed: ' + str(exc))
        compiler_help()
        return None, None
    if result.returncode:
        print(result.stderr)
        print('Visual C++ setup failed with status ' + str(result.returncode))
        compiler_help()
        return None, None
    environment = os.environ.copy()
    # Environment values can contain credentials. Consume them internally;
    # display the actual setup command but never dump environment values.
    for line in result.stdout.splitlines():
        key, separator, value = line.partition('=')
        if separator and key and not key.startswith('='):
            environment[key.upper()] = value
    print('Visual C++ environment loaded; environment values are not printed.')
    compiler = shutil.which('cl.exe', path=environment.get('PATH',''))
    return compiler, environment

def compile_command(compiler, source, build):
    if windows_host():
        return [compiler, '/nologo', '/EHsc', '/MT', source,
                '/Fe:' + str(build/'practical.exe'), '/Fo:' + str(build/'practical.obj')]
    return [compiler, '-std=c++11', source, '-o', build/'practical']

def prepare_runtime(number, source, no_gui=False, save=False):
    """Keep discovery/checks in a setup transcript, outside program output."""
    global LAST_SETUP_LOG
    try:
        handle, logname = tempfile.mkstemp(prefix='dsa-setup-',suffix='.log')
        os.close(handle)
    except OSError as exc:
        print('Cannot prepare the practical: ' + str(exc))
        help_error(exc,'setup')
        return None
    LAST_SETUP_LOG = logname
    build = None
    context = None
    with open(logname,'w',encoding='utf-8') as log, redirect_stdout(log), redirect_stderr(log):
        try:
            startup = os.environ.get('DSA_BOOTSTRAP_LOG')
            if startup and Path(startup).is_file():
                print(Path(startup).read_text(encoding='utf-8'))
            if save:
                save_source(number,source)
            if not Path(source).is_file():
                raise FileNotFoundError('Source file not found: ' + str(source))
            compiler, environment = find_compiler() if number <= 3 else (None,None)
            if number <= 3 and not compiler:
                compiler_help()
                raise RuntimeError('No usable C++ compiler is available.')
            environment = dict(environment or os.environ)
            path_key = 'PATH'
            folders = [str(Path(sys.executable).parent)]
            if compiler:
                folders.insert(0,str(Path(compiler).parent))
            environment[path_key] = os.pathsep.join(folders+[environment.get(path_key,'')])
            environment['DSA_SETUP_LOG'] = logname
            # Short actual command names; PATH points at the selected tools.
            python = Path(sys.executable).stem if windows_host() else Path(sys.executable).name
            compiler_name = (Path(compiler).stem if windows_host() else Path(compiler).name) if compiler else None
            # Never overwrite a user executable: create a unique local build dir.
            build = Path(tempfile.mkdtemp(prefix='.dsa-',dir=str(Path(source).resolve().parent)))
            build_relative = os.path.relpath(build,Path(source).resolve().parent)
            print('Isolated build folder: ' + str(build))
            if number == 10:
                imports = 'import numpy' if no_gui else 'import numpy; import matplotlib.pyplot'
                if execute([python,'-c',imports],'setup',True,env=environment) is None:
                    raise RuntimeError('Maze dependencies are unavailable.')
            context = {'compiler':compiler_name,'python':python,'build':build_relative,
                       'source':Path(source).name,'log':logname}
            (build/'run.json').write_text(json.dumps(context),encoding='utf-8')
            context['environment'] = environment
        except (OSError,RuntimeError) as exc:
            context = None
            print('Setup error: ' + str(exc))
            help_error(exc,'setup')
            if build is not None:
                shutil.rmtree(build,ignore_errors=True)
    if context is None:
        print(Path(logname).read_text(encoding='utf-8'),end='')
        print('Setup details: ' + logname)
    return context

def show(argv):
    print('$ ' + command_text(argv), flush=True)

def show_setup(argv):
    if LAST_SETUP_LOG:
        with open(LAST_SETUP_LOG,'a',encoding='utf-8') as log:
            print('$ ' + command_text(argv),file=log,flush=True)
    else:
        show(argv)

def cleanup_runtime(context, source):
    root = Path(source).resolve().parent
    build = root/context['build']
    if build.exists():
        if build.is_symlink() or build.resolve().parent != root or not build.name.startswith('.dsa-'):
            raise OSError('Refusing cleanup outside the isolated build folder.')
        shutil.rmtree(build)

def help_error(message, stage='execution', source=None):
    text = str(message)
    lower = text.lower()
    print('Help:', flush=True)
    missing = re.search(r"no module named ['\"]([^'\"]+)", text, re.I)
    if ('command not found' in lower or 'not recognized' in lower) and any(x in lower for x in ('g++', 'gcc', 'clang')):
        compiler_help()
    elif ('command not found' in lower or 'not recognized' in lower) and 'python' in lower:
        print('Install/repair Python 3 for Windows and reopen Git Bash.' if windows_host() else 'Missing Python 3.\nRun: sudo apt install python3\nThen start the launcher again.')
    elif missing:
        module = missing.group(1).split('.')[0]
        packages = {'numpy': 'python3-numpy', 'matplotlib': 'python3-matplotlib',
                    'tkinter': 'python3-tk'}
        if windows_host() and module in ('numpy','matplotlib'):
            print('Missing Python module ' + module + '.\nRun: ' + command_text([sys.executable,'-m','pip','install','numpy','matplotlib']) + '\nThen select the practical again.')
        elif windows_host() and module == 'tkinter':
            print('Repair your Windows Python installation and include Tcl/Tk support, or use --no-gui for maze text results.')
        elif module in packages:
            print(f'Missing Python module {module}.\nRun: sudo apt install {packages[module]}\nThen select the practical again.')
        else:
            print(f'Module {module} is unavailable. Check its spelling and use the same Python interpreter that has it installed.')
    elif any(s in lower for s in ('cannot connect to display', 'no display name', 'cannot open display', 'couldn\'t connect to display', 'invalid display')):
        print('No desktop display is available. Use an Ubuntu desktop session. For maze text output, select practical 10 with --no-gui.')
    elif 'externally-managed-environment' in lower:
        print('Ubuntu manages this Python environment. Run: sudo apt install python3-numpy python3-matplotlib python3-tk')
    elif any(s in lower for s in ('permission denied', 'access is denied', 'read-only file system', 'operation not permitted')):
        print('The folder or executable is not accessible. Move the launcher/source to a writable local working folder that permits execution. On Windows, close an executable still open in another terminal.')
    elif any(s in lower for s in ('no space left', 'disk full', 'not enough space')):
        print('The disk is full. Free space in the source and temporary folders, then select the practical again.')
    elif any(s in lower for s in ('no such file', 'cannot find', 'not found')):
        print('Check the displayed path. Restore the missing file or select the practical again to save a fresh source. Use a local folder if a USB drive was disconnected.')
    elif stage == 'compilation':
        if any(x in lower for x in ('cannot open include file', 'lnk1104', 'windows.h', 'cannot find link.exe')) and windows_host():
            print('The C++ headers, libraries, or Windows SDK are missing from this toolchain. Repair the Desktop development with C++ workload in Visual Studio Installer.')
        location = re.search(r'([^\n]+?):(\d+)(?::\d+)?:\s*(?:fatal )?error:', text)
        if location:
            print(f'Affected source: {location.group(1).strip()}, line {location.group(2)}.')
        msvc_location = re.search(r'([^\n]+?)\((\d+)(?:,\d+)?\)\s*:\s*(?:fatal )?error', text)
        if msvc_location:
            print(f'Affected source: {msvc_location.group(1).strip()}, line {msvc_location.group(2)}.')
        if 'ambiguous symbol' in lower or 'ambiguous' in lower:
            print('The reported name conflicts with another declaration. Rename your variable or qualify the intended namespace, then recompile.')
        elif 'expected' in lower:
            print('Correct the missing or misplaced token named by the compiler at the reported line; also check the preceding line for an unclosed bracket or quote.')
        elif 'not declared' in lower or 'undeclared' in lower:
            print('Check the reported identifier for a spelling error or missing declaration/header.')
        elif 'undefined reference' in lower:
            print('The linker cannot find the named definition. Restore the complete standalone source; it needs no extra project libraries.')
        elif 'syntaxerror' in lower or 'indentationerror' in lower:
            print('Fix the displayed Python line and its indentation, or select the practical again to restore the reviewed source.')
        else:
            print('Compilation stopped; the program was not run. Correct the first reported error, or select the practical again to restore the reviewed source.')
    elif any(s in lower for s in ('segmentation fault', 'access violation', 'signal 11', 'signal 6')):
        print('The program crashed. Restore the reviewed source by selecting the practical again; if it repeats, retain the input and error for diagnosis.')
    elif 'valueerror' in lower or 'invalid expression' in lower:
        print('Check the stated input rule. Practical 2 accepts single-character operands, binary + - * / ^ operators, and balanced parentheses.')
    elif 'memory' in lower:
        print('The requested data is too large for available memory. Retry with fewer records or a smaller maze.')
    elif 'backend' in lower or 'non-interactive' in lower or 'agg' in lower:
        print('Matplotlib has no interactive plotting backend. Repair Python with Tcl/Tk support, or use --no-gui for text results.' if windows_host() else 'Matplotlib has no interactive plotting backend. Run: sudo apt install python3-tk\nUse a desktop session and unset MPLBACKEND if it forces Agg, or use --no-gui for text results.')
    else:
        print(f'{stage.capitalize()} failed. Read the original error above and check the displayed command and path. Select the practical again to restore the reviewed source; keep the error and input if it repeats.')

def execute(argv, stage='execution', capture=False, env=None):
    show(argv)
    try:
        result = subprocess.run(list(map(str, argv)), text=True,
                                executable=resolve_tool(argv,env),
                                stdout=subprocess.PIPE if capture else None,
                                stderr=subprocess.STDOUT if capture else None,
                                errors='replace', env=env, timeout=60 if stage in ('compilation', 'setup', 'saving', 'cleanup') else None)
    except subprocess.TimeoutExpired as exc:
        if exc.stdout:
            print(exc.stdout.decode(errors='replace') if isinstance(exc.stdout, bytes) else exc.stdout)
        print(f'{stage.capitalize()} timed out after 60 seconds. Stop the stuck tool, check that its executable can run, and retry in a local writable folder. The practical was not started.', flush=True)
        return None
    except OSError as exc:
        print(f'{stage.capitalize()} error: {exc}', flush=True)
        help_error(exc, stage)
        return None
    if capture and result.stdout:
        print(result.stdout, end='' if result.stdout.endswith('\n') else '\n', flush=True)
    if result.returncode:
        detail = result.stdout if capture else ''
        status = f'Process ended with signal {-result.returncode}' if result.returncode < 0 else f'Exit status {result.returncode}'
        print(status, flush=True)
        help_error(detail or status, stage)
        return None
    return result

def resolve_tool(argv, env=None):
    # Windows CreateProcess does not search the supplied child's PATH. Resolve
    # the displayed short command against that same PATH explicitly.
    if windows_host():
        return shutil.which(str(argv[0]),path=(env or os.environ).get('PATH',''))
    return None

def filename(number):
    return f'DSA P{number}.' + ('cpp' if number <= 3 else 'py')

def save_source(number, destination):
    path = Path(destination)
    # Do not follow a source symlink or overwrite unrelated user content.
    if path.is_symlink():
        raise OSError('Refusing to overwrite a symbolic link: ' + str(path))
    if path.exists() and path.read_text(encoding='utf-8') != SOURCES[str(number)]:
        raise OSError('An existing file has different content: ' + str(path) +
                      '. Rename or move it first to preserve your edits, then select the practical again.')
    with path.open('w', encoding='utf-8', newline='\n') as stream:
        stream.write(SOURCES[str(number)])
    print('Saved source: ' + str(path), flush=True)

def live_program(argv, env=None):
    """Preserve interactive stdin and stream stdout/stderr, collecting diagnostics."""
    import threading
    show(argv)
    try:
        proc = subprocess.Popen(list(map(str, argv)), stderr=subprocess.PIPE,
                                text=True, errors='replace', env=env, executable=resolve_tool(argv,env))
        errors = []
        def relay():
            for line in proc.stderr:
                print(line, end='', file=sys.stderr, flush=True)
                errors.append(line)
                if len(errors) > 200:
                    errors.pop(0)
        thread = threading.Thread(target=relay, daemon=True)
        thread.start()
        try:
            status = proc.wait()
        except KeyboardInterrupt:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
            print('\nProgram interrupted by user.')
            status = 130
        thread.join()
        if status:
            detail = ''.join(errors)
            print(f'Process ended with signal {-status}.' if status < 0 else f'Program exit status: {status}', flush=True)
            help_error(detail or f'signal {-status}' if status < 0 else detail or f'exit status {status}')
        elif errors and any(x in ''.join(errors).lower() for x in ('backend', 'non-interactive', 'agg')):
            help_error(''.join(errors))
        return status
    except OSError as exc:
        print(f'Execution error: {exc}')
        help_error(exc)
        return 1

def worker(number, source, no_gui=False, prepared=None):
    source = str(Path(source).resolve())
    context = prepared or prepare_runtime(number,source,no_gui)
    if context is None:
        return 1
    root = Path(source).parent
    build = Path(context['build'])
    if build.is_absolute() or (root/build).is_symlink() or (root/build).resolve().parent != root or not build.name.startswith('.dsa-'):
        print('Invalid temporary build folder. Select the practical again.')
        return 1
    environment = context.get('environment')
    previous_folder = Path.cwd()
    os.chdir(root)
    try:
        source = context['source']
        if number <= 3:
            program = build / ('practical.exe' if windows_host() else 'practical')
            if execute(compile_command(context['compiler'], source, build), 'compilation', True, env=environment) is None:
                return 1
            command = ('.\\' if windows_host() else './') + str(program)
            return live_program([command],env=environment)
        try:
            py_compile.compile(source,cfile=str(build/'practical.pyc'),doraise=True)
        except py_compile.PyCompileError as exc:
            print(exc)
            help_error(exc,'compilation')
            return 1
        argv = [context['python'], '-u', source]
        if number == 10 and no_gui:
            argv.append('--no-gui')
        return live_program(argv,env=environment)
    except OSError as exc:
        print(f'Setup error: {exc}')
        help_error(exc, 'setup')
        return 1
    finally:
        try:
            cleanup_runtime(context,root/context['source'])
        except OSError as exc:
            print('Could not remove temporary build folder: ' + str(exc))
            help_error(exc,'cleanup')
        os.chdir(previous_folder)

def launch(number, here=False, no_gui=False):
    source = Path.cwd() / filename(number)
    context = prepare_runtime(number,source,no_gui,save=True)
    if context is None:
        return 1
    try:
        return launch_prepared(number,source,context,here,no_gui)
    finally:
        try:
            cleanup_runtime(context,source)
        except OSError as exc:
            print('Build-folder cleanup error: ' + str(exc))

def launch_prepared(number,source,context,here=False,no_gui=False):
    launcher = Path(__file__).resolve()
    if here:
        return worker(number, str(source), no_gui,prepared=context)
    if windows_host():
        editor = shutil.which('notepad.exe')
        if not editor:
            print('Windows Notepad is unavailable. Restore Notepad through Windows Optional Features, or use --here to run explicitly in this terminal.')
            return 1
        edit_cmd = [editor, str(source)]
        show_setup(edit_cmd)
        try:
            edit = subprocess.Popen(edit_cmd)
            try:
                status = edit.wait(timeout=1)
                if status:
                    help_error('Notepad startup exit status ' + str(status), 'editor startup')
                    return 1
            except subprocess.TimeoutExpired:
                pass
            argv = [sys.executable,str(launcher),'--worker',str(number),str(source)]
            argv += ['--prepared', str(Path(context['build'])/'run.json')]
            if no_gui:
                argv.append('--no-gui')
            show_setup(argv)
            # Wait so the standalone shell's temporary launcher remains alive
            # until the output terminal has finished using it.
            output = subprocess.Popen(argv,cwd=str(source.parent),env=context['environment'],creationflags=subprocess.CREATE_NEW_CONSOLE)
            return output.wait()
        except OSError as exc:
            print('Windows window startup failed: ' + str(exc))
            help_error(exc,'terminal startup')
            return 1
    # Discover desktop tools before starting either window.
    terminal = next((shutil.which(x) for x in ['gnome-terminal', 'konsole', 'xfce4-terminal', 'mate-terminal', 'xterm'] if shutil.which(x)), None)
    editor = next((shutil.which(x) for x in ['gnome-text-editor', 'gedit', 'kate', 'mousepad', 'pluma', 'xed', 'leafpad'] if shutil.which(x)), None)
    if not terminal:
        print('Missing desktop terminal.\nRun: sudo apt install gnome-terminal\nThen select the practical again. For a terminal-only session, run with --here explicitly.')
        return 1
    if not editor:
        print('Missing desktop text editor.\nRun: sudo apt install gnome-text-editor\nThen select the practical again.')
        return 1
    if not (os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY')):
        help_error('Cannot open display', 'setup')
        return 1
    edit_cmd = [editor, str(source)]
    # Most desktop editors return once their window is open. Wait for the launch
    # command so startup errors are caught. The source is not edited by us here.
    show_setup(edit_cmd)
    try:
        edit = subprocess.Popen(edit_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        try:
            _, err = edit.communicate(timeout=1)
            if edit.returncode:
                print(err)
                help_error(err, 'editor startup')
                return 1
        except subprocess.TimeoutExpired:
            # Drain late startup errors without blocking a long-lived editor.
            import threading
            def watch_editor():
                _, err = edit.communicate()
                if edit.returncode:
                    print(err)
                    help_error(err, 'editor startup')
            threading.Thread(target=watch_editor, daemon=True).start()
    except OSError as exc:
        print(exc)
        help_error(exc, 'editor startup')
        return 1
    argv = [sys.executable, str(launcher), '--worker', str(number), str(source)]
    argv += ['--prepared',str(Path(context['build'])/'run.json')]
    if no_gui:
        argv.append('--no-gui')
    # Use argv, never interpolate file names into shell code.
    if Path(terminal).name == 'gnome-terminal':
        terminal_cmd = [terminal, '--wait', '--working-directory=' + str(source.parent), '--'] + argv
    elif Path(terminal).name == 'xfce4-terminal':
        terminal_cmd = [terminal, '--disable-server', '--working-directory=' + str(source.parent), '-x'] + argv
    elif Path(terminal).name == 'mate-terminal':
        terminal_cmd = [terminal, '--disable-factory', '--working-directory=' + str(source.parent), '-x'] + argv
    elif Path(terminal).name == 'konsole':
        terminal_cmd = [terminal, '--nofork', '--workdir', str(source.parent), '-e'] + argv
    else:
        terminal_cmd = [terminal, '-e'] + argv
    with open(context['log'],'a',encoding='utf-8') as log, redirect_stdout(log):
        result = execute(terminal_cmd,'terminal startup',True,env=context['environment'])
    if result is None:
        print(Path(context['log']).read_text(encoding='utf-8'),end='')
        return 1
    return 0

def choose_practical():
    for number, title in enumerate(TITLES, 1):
        print(f'{number}. {title}')
    while True:
        value = input('Practical number (1-10, B to go back): ').strip()
        if value.lower() == 'b':
            return None
        if value.isdigit() and 1 <= int(value) <= 10:
            return int(value)
        print('Enter a number from 1 to 10, or B.')

def show_writeup(number):
    guide = GUIDES[number]
    print(f'\nPRACTICAL {number}: {TITLES[number-1]}')
    for label, key in [('Aim','aim'),('Theory','theory'),('Algorithm','algorithm')]:
        print(f'\n{label}:\n{guide[key]}')
    print('\nCorrected program:\n' + SOURCES[str(number)])
    for label, key in [('Sample input / procedure','sample'),
                       ('Expected output (key results)','output'),
                       ('Complexity','complexity')]:
        print(f'\n{label}:\n{guide[key]}')
    print('\nConclusion:\nThe listed operations and sample results illustrate ' + TITLES[number-1].lower() + '.')
    print('\nVerification note: these reference results do not certify Ubuntu execution. See the review and test status.')

def pasted_error_help():
    print('Paste the error; finish with an empty line:')
    lines = []
    while True:
        line = input()
        if not line:
            break
        lines.append(line)
    message = '\n'.join(lines)
    if message:
        help_error(message, 'compilation' if any(x in message.lower() for x in ('error:', 'syntaxerror', 'indentationerror')) else 'execution')
    else:
        print('No error entered.')

def explanation_menu():
    while True:
        print('\nEXPLANATION AND ERROR HELP\n1. Explain a practical\n2. Viva questions and answers\n3. Error help (paste an error)\n4. Platform setup and troubleshooting\n5. View corrected code with line numbers\n6. Corrections and edge cases\n7. Last setup details\nB. Back to main menu')
        choice = input('Choose: ').strip().lower()
        if choice == 'b':
            return
        if choice == '3':
            pasted_error_help()
        elif choice == '7':
            logpath = LAST_SETUP_LOG or os.environ.get('DSA_SETUP_LOG')
            if logpath and Path(logpath).is_file():
                print(Path(logpath).read_text(encoding='utf-8'))
            else:
                print('No practical setup has run in this session yet.')
        elif choice == '4':
            if windows_host():
                print('''Windows setup and troubleshooting:
Run the .sh file using Git Bash: bash dsa.sh
Python 3.8+ must be installed. The launcher tries command alternatives automatically.
For practicals 1-3, install/repair Visual Studio Build Tools with Desktop development with C++ and a Windows SDK.
The launcher finds installed Visual C++ tools and loads their environment automatically. MinGW is not used.
Notepad opens the source; a new Windows console accepts program input and pauses after completion.
For maze libraries, use the pip command below with the selected interpreter:''')
                print(command_text([sys.executable,'-m','pip','install','numpy','matplotlib']))
                print('Use --no-gui for maze text output. Use --here explicitly for the existing terminal. No tools are installed automatically.')
                continue
            print('''Ubuntu setup and troubleshooting:
The shell launcher probes Python command alternatives automatically. All operations use the selected interpreter.
Only run an installation command when its tool is missing:
Python: sudo apt install python3
C++ compiler: sudo apt install build-essential
Desktop terminal: sudo apt install gnome-terminal
Desktop text editor: sudo apt install gnome-text-editor
Maze libraries/backend: sudo apt install python3-numpy python3-matplotlib python3-tk
No packages are installed automatically.
Use a writable local working folder; quote paths containing spaces.
If a source already contains different edits, rename it or use an empty folder.
The new output terminal accepts practical input and stays open until Enter after completion.
For maze plots, close each window to continue; --no-gui requests text results.
For a terminal-only session, explicitly use --here; it does not open an editor/window.
Compile/setup commands stop after 60 seconds; Ctrl+C interrupts an interactive practical.
Automatic error help appears after recognized failures; use option 3 for other pasted diagnostics.
Ubuntu compilation, execution, desktop windows, and interactive plotting remain unverified on this Windows development host.''')
        elif choice in ('1','2','5','6'):
            number = choose_practical()
            if number is None:
                continue
            guide = GUIDES[number]
            print(f'\nPRACTICAL {number}: {TITLES[number-1]}')
            if choice == '1':
                for label,key in [('How the code works','explanation'),('Algorithm','algorithm'),('Complexity','complexity')]:
                    print(f'\n{label}:\n{guide[key]}')
            elif choice == '2':
                print(guide['viva'])
            elif choice == '5':
                for line,text in enumerate(SOURCES[str(number)].splitlines(),1):
                    print(f'{line:4}: {text}')
            else:
                print('Corrections:\n' + guide['fixes'] + '\n\nEdge cases:\n' + guide['edges'])
        else:
            print('Choose 1-7 or B.')

def show_manual_commands(number):
    source = Path.cwd()/filename(number)
    launcher = Path(__file__).resolve()
    python = command_text([sys.executable])
    if windows_host():
        print(f'\nWINDOWS COMMANDS: Practical {number} - {TITLES[number-1]}')
        print('Reference commands for Command Prompt; this menu does not execute them.')
        print('Save source, then use the automatic worker to display all actual setup/compile/run commands:')
        print('$ ' + command_text([sys.executable,launcher,'--save-source',str(number),source]))
        print('$ ' + command_text([sys.executable,launcher,'--worker',str(number),source]))
        print('These temporary launcher paths remain valid while the menu is open.')
        print('For direct compilation, use an x64 Native Tools Command Prompt and create a temporary folder:')
        print('$ ' + command_text([sys.executable,'-c',"import tempfile; print(tempfile.mkdtemp(prefix='dsa-build-'))"]))
        print('Copy the printed folder path into this variable:')
        print('$ set "DSA_BUILD=PASTE_THE_PRINTED_FOLDER_PATH_HERE"')
        if number <= 3:
            cmd = command_text(['cl.exe','/nologo','/EHsc','/std:c++14','/W4','/MT',source])
            print('$ ' + cmd + ' /Fe:"%DSA_BUILD%\\practical.exe" /Fo:"%DSA_BUILD%\\practical.obj" && "%DSA_BUILD%\\practical.exe"')
        else:
            check = command_text([sys.executable,'-c','import py_compile,sys; py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)',source])
            command = check + ' "%DSA_BUILD%\\practical.pyc"'
            if number == 10:
                command += ' && ' + command_text([sys.executable,'-c','import numpy; import matplotlib.pyplot'])
            command += ' && ' + command_text([sys.executable,'-u',source])
            print('$ ' + command)
        print('After completion, remove only that temporary build folder:')
        print('$ ' + command_text([sys.executable,'-c','import shutil,sys; shutil.rmtree(sys.argv[1])']) + ' "%DSA_BUILD%"')
        print('This practical has one source file and no supporting processes. MinGW is excluded.')
        return
    quoted_source = shlex.quote(str(source))
    print(f'\nUBUNTU COMMANDS: Practical {number} - {TITLES[number-1]}')
    print('Reference commands below are shown for you to run manually; they are not executed by this menu.')
    print('Run from the folder where you want the source. This saves the bundled source and protects existing edits:')
    save = command_text([sys.executable, launcher, '--save-source', str(number), str(source)])
    print('$ ' + save)
    print('The launcher path above is valid while this menu remains open. After closing it, use bash dsa.sh --extract instead.')
    editor = next((shutil.which(x) for x in ['gnome-text-editor','gedit','kate','mousepad','pluma','xed','nano'] if shutil.which(x)), 'nano')
    print('Open the saved code in an editor:')
    print('$ ' + command_text([editor,source]))
    print('Build and run in your input terminal. The && chain prevents running after a failed check:')
    if number <= 3:
        compile_run = f'g++ -std=c++11 -Wall -Wextra -pedantic {quoted_source} -o "$build_dir/practical" && "$build_dir/practical"'
    else:
        check = shlex.quote('import py_compile,sys; py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)')
        compile_run = f'{python} -c {check} {quoted_source} "$build_dir/practical.pyc"'
        if number == 10:
            compile_run += ' && ' + python + ' -c ' + shlex.quote('import numpy; import matplotlib.pyplot')
        compile_run += f' && {python} -u {quoted_source}'
    print('$ ' + save + ' && build_dir=$(mktemp -d -t dsa-build.XXXXXXXX) && ' + compile_run)
    print('mktemp chooses an isolated folder; the automatic runner displays its actual full path.')
    print('After the program ends, remove only that build folder:')
    print('$ ' + python + ' -c ' + shlex.quote('import shutil,sys; shutil.rmtree(sys.argv[1])') + ' "$build_dir"')
    if number == 10:
        print('Text-only alternative: use the Python run command with --no-gui. Then only NumPy is required. Close each plot window in graphical mode to continue.')
    print('This practical has one source file and no supporting-file or second-process commands.')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('number', nargs='?', type=int, choices=range(1, 11))
    parser.add_argument('--here', action='store_true', help='explicitly run in this terminal without opening an editor')
    parser.add_argument('--no-gui', action='store_true', help='maze text results only')
    parser.add_argument('--worker', nargs=2, metavar=('NUMBER', 'SOURCE'))
    parser.add_argument('--prepared',help=argparse.SUPPRESS)
    parser.add_argument('--save-source', nargs=2, metavar=('NUMBER', 'PATH'))
    parser.add_argument('--extract', action='store_true', help='save reviewed sources in the current folder without running them')
    args = parser.parse_args()
    if args.extract:
        try:
            for n in range(1,11):
                save_source(n,Path.cwd()/filename(n))
        except (OSError, UnicodeError) as exc:
            print(f'Saving error: {exc}\nRecovery: use a writable, empty folder to preserve any existing files.')
            return 1
        return 0
    if args.save_source:
        try:
            save_source(int(args.save_source[0]), args.save_source[1])
        except (OSError, UnicodeError) as exc:
            print(f'Saving error: {exc}')
            if 'different content' in str(exc) or 'symbolic link' in str(exc):
                print('Recovery: rename the existing file or use an empty working folder, then select the practical again.')
            else:
                help_error(exc, 'saving')
            return 1
        return 0
    if not (sys.platform.startswith('linux') or windows_host()):
        print('Supported platforms: Ubuntu/Linux or Windows (Git Bash for the .sh file).')
        return 1
    if args.worker:
        try:
            folder = str(Path(args.worker[1]).resolve().parent)
            os.chdir(folder)
            prepared = json.loads(Path(args.prepared).read_text(encoding='utf-8')) if args.prepared else None
            status = worker(int(args.worker[0]), args.worker[1], args.no_gui,prepared=prepared)
        except (OSError,ValueError,KeyError) as exc:
            print(exc)
            help_error(exc, 'setup')
            status = 1
        finally:
            try:
                input('\nPress Enter to close...')
            except (EOFError, KeyboardInterrupt):
                pass
        return status
    if args.number:
        return launch(args.number, args.here, args.no_gui)
    while True:
        print('\nDSA PRACTICALS\n1. Run a practical\n2. Practical write-up\n3. Explanation and error help\n4. Commands to run practicals\nQ. Exit')
        choice = input('Choose: ').strip().lower()
        if choice == 'q':
            return 0
        if choice == '3':
            explanation_menu()
        elif choice in ('1','2','4'):
            number = choose_practical()
            if number is None:
                continue
            if choice == '1':
                launch(number, args.here, args.no_gui)
            elif choice == '2':
                show_writeup(number)
            else:
                show_manual_commands(number)
        else:
            print('Choose 1-4 or Q.')

if __name__ == '__main__':
    try:
        sys.exit(main())
    except (EOFError, KeyboardInterrupt):
        print('\nLauncher closed.')

DSA_PYTHON_PAYLOAD_2026
if [[ $? != 0 ]]; then
    printf 'Cannot save launcher. Check free space and temporary-folder permissions.\n'
    exit 1
fi
show_command "${python_cmd[@]}" "$runner" "$@" >> "$bootstrap_log"
"${python_cmd[@]}" "$runner" "$@"
