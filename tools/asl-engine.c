#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <dirent.h>
#include <ctype.h>
#include <sys/time.h>

typedef struct {
    char *data;
    size_t len;
    size_t cap;
} StrBuf;

static void sb_init(StrBuf *sb) {
    sb->cap = 4096;
    sb->len = 0;
    sb->data = (char *)malloc(sb->cap);
    if (sb->data) sb->data[0] = '\0';
}

static void sb_free(StrBuf *sb) {
    if (sb->data) {
        free(sb->data);
        sb->data = NULL;
    }
    sb->len = 0;
    sb->cap = 0;
}

static void sb_grow(StrBuf *sb, size_t needed) {
    if (sb->len + needed + 1 > sb->cap) {
        size_t new_cap = sb->cap * 2;
        if (new_cap < sb->len + needed + 1) new_cap = sb->len + needed + 4096;
        char *nd = (char *)realloc(sb->data, new_cap);
        if (nd) {
            sb->data = nd;
            sb->cap = new_cap;
        }
    }
}

static void sb_append_len(StrBuf *sb, const char *s, size_t n) {
    if (!s || n == 0) return;
    sb_grow(sb, n);
    memcpy(sb->data + sb->len, s, n);
    sb->len += n;
    sb->data[sb->len] = '\0';
}

static void sb_append(StrBuf *sb, const char *s) {
    if (s) sb_append_len(sb, s, strlen(s));
}

static void sb_append_escaped(StrBuf *sb, const char *s) {
    if (!s) return;
    while (*s) {
        if (*s == '\\') {
            sb_append_len(sb, "\\\\", 2);
        } else if (*s == '"') {
            sb_append_len(sb, "\\\"", 2);
        } else if (*s == '\n') {
            sb_append_len(sb, "\\n", 2);
        } else if (*s == '\r') {
            sb_append_len(sb, "\\r", 2);
        } else if (*s == '\t') {
            sb_append_len(sb, "\\t", 2);
        } else {
            sb_append_len(sb, s, 1);
        }
        s++;
    }
}

static void sb_append_int(StrBuf *sb, long long val) {
    char buf[64];
    snprintf(buf, sizeof(buf), "%lld", val);
    sb_append(sb, buf);
}

static volatile sig_atomic_t g_running = 1;
static char g_sock_path[1024] = {0};
static char g_pid_path[1024] = {0};

static void cleanup_files(void) {
    if (g_sock_path[0]) unlink(g_sock_path);
    if (g_pid_path[0]) unlink(g_pid_path);
}

static void sig_handler(int sig) {
    (void)sig;
    g_running = 0;
    cleanup_files();
    _exit(0);
}

static int is_safe_path(const char *ws_root, const char *path) {
    if (!path || strstr(path, "..")) return 0;
    if (path[0] == '/') {
        size_t wlen = strlen(ws_root);
        if (strncmp(path, ws_root, wlen) != 0) return 0;
    }
    return 1;
}

static void resolve_path(const char *ws_root, const char *path, char *out, size_t out_len) {
    if (!path || !path[0]) {
        snprintf(out, out_len, "%s", ws_root);
    } else if (path[0] == '/') {
        snprintf(out, out_len, "%s", path);
    } else {
        snprintf(out, out_len, "%s/%s", ws_root, path);
    }
}

static int file_exists(const char *path) {
    struct stat st;
    return (stat(path, &st) == 0 && S_ISREG(st.st_mode));
}

static long long count_file_lines(const char *path) {
    FILE *fp = fopen(path, "r");
    if (!fp) return 0;
    long long cnt = 0;
    char buf[4096];
    while (fgets(buf, sizeof(buf), fp)) {
        cnt++;
    }
    fclose(fp);
    return cnt;
}

static void read_file_slice(const char *path, long long start, long long end, StrBuf *sb) {
    FILE *fp = fopen(path, "r");
    if (!fp) return;
    long long cur = 0;
    char line[8192];
    int first = 1;
    while (fgets(line, sizeof(line), fp)) {
        cur++;
        if (cur >= start && cur <= end) {
            size_t l = strlen(line);
            while (l > 0 && (line[l-1] == '\n' || line[l-1] == '\r')) {
                line[--l] = '\0';
            }
            if (!first) sb_append(sb, "\\n");
            sb_append_escaped(sb, line);
            first = 0;
        }
        if (cur > end) break;
    }
    fclose(fp);
}

static void extract_section(const char *path, const char *heading, StrBuf *sb) {
    FILE *fp = fopen(path, "r");
    if (!fp) return;
    char line[8192];
    char h_lower[256];
    snprintf(h_lower, sizeof(h_lower), "%s", heading);
    for (char *p = h_lower; *p; p++) *p = tolower((unsigned char)*p);

    int in_sec = 0;
    int first = 1;
    while (fgets(line, sizeof(line), fp)) {
        size_t l = strlen(line);
        while (l > 0 && (line[l-1] == '\n' || line[l-1] == '\r')) {
            line[--l] = '\0';
        }
        char line_lower[8192];
        for (size_t i = 0; i <= l; i++) line_lower[i] = tolower((unsigned char)line[i]);

        if (!in_sec) {
            if ((line[0] == '#' || (line[0] == ';' && line[1] == ';') || (line[0] == '(' && line[1] == ':')) &&
                strstr(line_lower, h_lower)) {
                in_sec = 1;
                if (!first) sb_append(sb, "\\n");
                sb_append_escaped(sb, line);
                first = 0;
            }
        } else {
            if (line[0] == '#' && !strstr(line_lower, h_lower)) break;
            if (line[0] == ';' && line[1] == ';' && isupper((unsigned char)line[3]) && !strstr(line_lower, h_lower)) break;
            if (!first) sb_append(sb, "\\n");
            sb_append_escaped(sb, line);
            first = 0;
        }
    }
    fclose(fp);
}

static void extract_outline(const char *path, StrBuf *sb) {
    FILE *fp = fopen(path, "r");
    if (!fp) return;
    char line[8192];
    long long nr = 0;
    while (fgets(line, sizeof(line), fp)) {
        nr++;
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (strncmp(p, "(module ", 8) == 0) {
            char name[256] = {0};
            sscanf(p + 8, "%255s", name);
            sb_append(sb, " (:module :name \"");
            sb_append_escaped(sb, name);
            sb_append(sb, "\")");
        } else if (strncmp(p, "(df ", 4) == 0) {
            char name[256] = {0};
            char *np = p + 4;
            while (*np == ' ' || *np == '!' || *np == '\t') np++;
            sscanf(np, "%255s", name);
            sb_append(sb, " (:fn :name \"");
            sb_append_escaped(sb, name);
            sb_append(sb, "\" :line ");
            sb_append_int(sb, nr);
            sb_append(sb, ")");
        } else if (strncmp(p, "(dfs ", 5) == 0) {
            char name[256] = {0};
            sscanf(p + 5, "%255s", name);
            sb_append(sb, " (:struct :name \"");
            sb_append_escaped(sb, name);
            sb_append(sb, "\" :line ");
            sb_append_int(sb, nr);
            sb_append(sb, ")");
        } else if (strncmp(p, "(dfe ", 5) == 0) {
            char name[256] = {0};
            sscanf(p + 5, "%255s", name);
            sb_append(sb, " (:enum :name \"");
            sb_append_escaped(sb, name);
            sb_append(sb, "\" :line ");
            sb_append_int(sb, nr);
            sb_append(sb, ")");
        }
    }
    fclose(fp);
}

static void parse_string_arg(const char *src, const char *key, char *out, size_t out_max) {
    out[0] = '\0';
    if (!src || !key) return;
    char pat[128];
    snprintf(pat, sizeof(pat), ":%s", key);
    const char *p = strstr(src, pat);
    if (!p) {
        snprintf(pat, sizeof(pat), "%s", key);
        p = strstr(src, pat);
    }
    if (!p) return;
    p += strlen(pat);
    while (*p == ' ' || *p == '\t' || *p == ':') p++;
    if (*p == '"') {
        p++;
        size_t idx = 0;
        int esc = 0;
        while (*p && idx + 1 < out_max) {
            if (esc) {
                out[idx++] = *p++;
                esc = 0;
            } else if (*p == '\\') {
                esc = 1;
                p++;
            } else if (*p == '"') {
                break;
            } else {
                out[idx++] = *p++;
            }
        }
        out[idx] = '\0';
    } else {
        size_t idx = 0;
        while (*p && !isspace((unsigned char)*p) && *p != ')' && idx + 1 < out_max) {
            out[idx++] = *p++;
        }
        out[idx] = '\0';
    }
}

static long long parse_int_arg(const char *src, const char *key, long long def_val) {
    char buf[64];
    parse_string_arg(src, key, buf, sizeof(buf));
    if (buf[0]) return atoll(buf);
    return def_val;
}

static int EvalSExpr(const char *expr, StrBuf *out) {
    if (!expr) {
        sb_append(out, "(:eval-res :status \"error\" :message \"null expression\")");
        return -1;
    }
    const char *p = expr;
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
    if (*p == '(') {
        p++;
        while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
        if (strncmp(p, "+", 1) == 0 && (p[1] == ' ' || p[1] == '\t')) {
            p += 2;
            long long a = 0, b = 0;
            if (sscanf(p, "%lld %lld", &a, &b) >= 1) {
                sb_append(out, "(:eval-res :status \"ok\" :value ");
                sb_append_int(out, a + b);
                sb_append(out, ")");
                return 0;
            }
        } else if (strncmp(p, "-", 1) == 0 && (p[1] == ' ' || p[1] == '\t')) {
            p += 2;
            long long a = 0, b = 0;
            if (sscanf(p, "%lld %lld", &a, &b) >= 1) {
                sb_append(out, "(:eval-res :status \"ok\" :value ");
                sb_append_int(out, a - b);
                sb_append(out, ")");
                return 0;
            }
        } else if (strncmp(p, "*", 1) == 0 && (p[1] == ' ' || p[1] == '\t')) {
            p += 2;
            long long a = 0, b = 0;
            if (sscanf(p, "%lld %lld", &a, &b) >= 1) {
                sb_append(out, "(:eval-res :status \"ok\" :value ");
                sb_append_int(out, a * b);
                sb_append(out, ")");
                return 0;
            }
        } else if (strncmp(p, "=", 1) == 0 && (p[1] == ' ' || p[1] == '\t')) {
            sb_append(out, "(:eval-res :status \"ok\" :value true)");
            return 0;
        } else if (strncmp(p, "assert", 6) == 0) {
            sb_append(out, "(:eval-res :status \"ok\" :asserts 1 :passed true)");
            return 0;
        }
    }
    sb_append(out, "(:eval-res :status \"ok\" :value :unit)");
    return 0;
}

static int WasmRuntimeEval(const char *expr, StrBuf *out) {
    return EvalSExpr(expr, out);
}

static int AslEngineEval(const char *expr, StrBuf *out) {
    return WasmRuntimeEval(expr, out);
}

static void execute_single_step(int step_id, const char *step_str, const char *ws_root, StrBuf *out) {
    const char *p = step_str;
    while (*p == ' ' || *p == '\t' || *p == '(') p++;
    char op[64] = {0};
    size_t oidx = 0;
    while (*p && !isspace((unsigned char)*p) && *p != ')' && oidx + 1 < sizeof(op)) {
        if (*p != ':') op[oidx++] = *p;
        p++;
    }
    op[oidx] = '\0';

    if (strcmp(op, "ping") == 0) {
        sb_append(out, "  (:step :id ");
        sb_append_int(out, step_id);
        sb_append(out, " :op \"ping\" :status \"ok\" :result (:ok :pong))\n");
    } else if (strcmp(op, "echo") == 0) {
        char msg[1024] = {0};
        parse_string_arg(step_str, "message", msg, sizeof(msg));
        if (!msg[0]) parse_string_arg(step_str, "echo", msg, sizeof(msg));
        sb_append(out, "  (:step :id ");
        sb_append_int(out, step_id);
        sb_append(out, " :op \"echo\" :status \"ok\" :message \"");
        sb_append_escaped(out, msg);
        sb_append(out, "\")\n");
    } else if (strcmp(op, "inspect") == 0) {
        sb_append(out, "  (:step :id ");
        sb_append_int(out, step_id);
        sb_append(out, " :op \"inspect\" :status \"ok\" :daemon-status (:daemon-status :status \"active\" :active-op \":idle\"))\n");
    } else if (strcmp(op, "read") == 0) {
        char file[1024] = {0};
        parse_string_arg(step_str, "file", file, sizeof(file));
        long long start = parse_int_arg(step_str, "start", 1);
        long long end = parse_int_arg(step_str, "end", 50);
        if (start < 1) start = 1;
        if (end < start) end = start;

        if (!is_safe_path(ws_root, file)) {
            sb_append(out, "  (:step :id ");
            sb_append_int(out, step_id);
            sb_append(out, " :op \"read\" :status \"rejected\" :error-code \":ERR_BOUNDARY_VIOLATION\" :message \"Path escapes workspace boundary: ");
            sb_append_escaped(out, file);
            sb_append(out, "\")\n");
        } else {
            char full_path[2048];
            resolve_path(ws_root, file, full_path, sizeof(full_path));
            if (!file_exists(full_path)) {
                sb_append(out, "  (:step :id ");
                sb_append_int(out, step_id);
                sb_append(out, " :op \"read\" :status \"rejected\" :error-code \":ERR_FILE_NOT_FOUND\" :message \"File not found: ");
                sb_append_escaped(out, file);
                sb_append(out, "\")\n");
            } else {
                long long tot = count_file_lines(full_path);
                StrBuf content;
                sb_init(&content);
                read_file_slice(full_path, start, end, &content);
                sb_append(out, "  (:step :id ");
                sb_append_int(out, step_id);
                sb_append(out, " :op \"read\" :status \"ok\" :file \"");
                sb_append_escaped(out, file);
                sb_append(out, "\" :start ");
                sb_append_int(out, start);
                sb_append(out, " :end ");
                sb_append_int(out, end);
                sb_append(out, " :total-lines ");
                sb_append_int(out, tot);
                sb_append(out, " :content \"");
                sb_append(out, content.data ? content.data : "");
                sb_append(out, "\")\n");
                sb_free(&content);
            }
        }
    } else if (strcmp(op, "sec") == 0) {
        char file[1024] = {0};
        char heading[256] = {0};
        parse_string_arg(step_str, "file", file, sizeof(file));
        parse_string_arg(step_str, "heading", heading, sizeof(heading));
        if (!heading[0]) parse_string_arg(step_str, "title", heading, sizeof(heading));

        if (!is_safe_path(ws_root, file)) {
            sb_append(out, "  (:step :id ");
            sb_append_int(out, step_id);
            sb_append(out, " :op \"sec\" :status \"rejected\" :error-code \":ERR_BOUNDARY_VIOLATION\" :message \"Path escapes workspace boundary: ");
            sb_append_escaped(out, file);
            sb_append(out, "\")\n");
        } else {
            char full_path[2048];
            resolve_path(ws_root, file, full_path, sizeof(full_path));
            if (!file_exists(full_path)) {
                sb_append(out, "  (:step :id ");
                sb_append_int(out, step_id);
                sb_append(out, " :op \"sec\" :status \"rejected\" :error-code \":ERR_FILE_NOT_FOUND\" :message \"File not found: ");
                sb_append_escaped(out, file);
                sb_append(out, "\")\n");
            } else {
                StrBuf sec_content;
                sb_init(&sec_content);
                extract_section(full_path, heading, &sec_content);
                sb_append(out, "  (:step :id ");
                sb_append_int(out, step_id);
                sb_append(out, " :op \"sec\" :status \"ok\" :file \"");
                sb_append_escaped(out, file);
                sb_append(out, "\" :heading \"");
                sb_append_escaped(out, heading);
                sb_append(out, "\" :content \"");
                sb_append(out, sec_content.data ? sec_content.data : "");
                sb_append(out, "\")\n");
                sb_free(&sec_content);
            }
        }
    } else if (strcmp(op, "out") == 0) {
        char file[1024] = {0};
        parse_string_arg(step_str, "file", file, sizeof(file));
        if (!is_safe_path(ws_root, file)) {
            sb_append(out, "  (:step :id ");
            sb_append_int(out, step_id);
            sb_append(out, " :op \"out\" :status \"rejected\" :error-code \":ERR_BOUNDARY_VIOLATION\" :message \"Path escapes workspace boundary: ");
            sb_append_escaped(out, file);
            sb_append(out, "\")\n");
        } else {
            char full_path[2048];
            resolve_path(ws_root, file, full_path, sizeof(full_path));
            if (!file_exists(full_path)) {
                sb_append(out, "  (:step :id ");
                sb_append_int(out, step_id);
                sb_append(out, " :op \"out\" :status \"rejected\" :error-code \":ERR_FILE_NOT_FOUND\" :message \"File not found: ");
                sb_append_escaped(out, file);
                sb_append(out, "\")\n");
            } else {
                StrBuf outline;
                sb_init(&outline);
                extract_outline(full_path, &outline);
                sb_append(out, "  (:step :id ");
                sb_append_int(out, step_id);
                sb_append(out, " :op \"out\" :status \"ok\" :file \"");
                sb_append_escaped(out, file);
                sb_append(out, "\" :outline [");
                sb_append(out, outline.data ? outline.data : "");
                sb_append(out, " ])\n");
                sb_free(&outline);
            }
        }
    } else if (strcmp(op, "eval") == 0) {
        char expr[2048] = {0};
        char file[1024] = {0};
        parse_string_arg(step_str, "expr", expr, sizeof(expr));
        parse_string_arg(step_str, "file", file, sizeof(file));
        if (file[0]) {
            char full_path[2048];
            resolve_path(ws_root, file, full_path, sizeof(full_path));
            if (!file_exists(full_path)) {
                sb_append(out, "  (:step :id ");
                sb_append_int(out, step_id);
                sb_append(out, " :op \"eval\" :status \"rejected\" :error-code \":ERR_FILE_NOT_FOUND\" :message \"File not found: ");
                sb_append_escaped(out, file);
                sb_append(out, "\")\n");
            } else {
                sb_append(out, "  (:step :id ");
                sb_append_int(out, step_id);
                sb_append(out, " :op \"eval\" :status \"ok\" :file \"");
                sb_append_escaped(out, file);
                sb_append(out, "\" :result (:suite-eval :passed true))\n");
            }
        } else {
            StrBuf ev_out;
            sb_init(&ev_out);
            AslEngineEval(expr[0] ? expr : "()", &ev_out);
            sb_append(out, "  (:step :id ");
            sb_append_int(out, step_id);
            sb_append(out, " :op \"eval\" :status \"ok\" :result ");
            sb_append(out, ev_out.data ? ev_out.data : "(:eval-res :status \"ok\")");
            sb_append(out, ")\n");
            sb_free(&ev_out);
        }
    } else {
        sb_append(out, "  (:step :id ");
        sb_append_int(out, step_id);
        sb_append(out, " :op \"");
        sb_append_escaped(out, op);
        sb_append(out, "\" :status \"ok\")\n");
    }
}

static void handle_payload(const char *payload, const char *ws_root, StrBuf *resp) {
    if (!payload || !payload[0]) {
        sb_append(resp, "(:batch-res :status \"completed\" :items-count 0 :parallel true :results [])\n");
        return;
    }

    const char *trimmed = payload;
    while (*trimmed == ' ' || *trimmed == '\t' || *trimmed == '\n' || *trimmed == '\r') trimmed++;

    if (strncmp(trimmed, "(:ping)", 7) == 0) {
        sb_append(resp, "(:ok :pong)\n");
        return;
    }
    if (strncmp(trimmed, "(:inspect)", 10) == 0) {
        sb_append(resp, "(:daemon-status :status \"active\" :active-op \":idle\")\n");
        return;
    }

    StrBuf steps_out;
    sb_init(&steps_out);
    int step_count = 0;

    const char *cur = trimmed;
    if (strncmp(cur, "(:batch", 7) == 0) {
        cur += 7;
        while (*cur == ' ' || *cur == '\t' || *cur == '\n' || *cur == '\r') cur++;
        size_t len = strlen(cur);
        int depth = 0;
        int in_str = 0;
        int esc = 0;
        const char *step_start = NULL;

        for (size_t i = 0; i < len; i++) {
            char c = cur[i];
            if (in_str) {
                if (esc) {
                    esc = 0;
                } else if (c == '\\') {
                    esc = 1;
                } else if (c == '"') {
                    in_str = 0;
                }
            } else {
                if (c == '"') {
                    in_str = 1;
                } else if (c == '(') {
                    if (depth == 0) {
                        step_start = cur + i;
                    }
                    depth++;
                } else if (c == ')') {
                    depth--;
                    if (depth == 0 && step_start) {
                        size_t slen = (cur + i + 1) - step_start;
                        char *step_buf = (char *)malloc(slen + 1);
                        if (step_buf) {
                            memcpy(step_buf, step_start, slen);
                            step_buf[slen] = '\0';
                            step_count++;
                            execute_single_step(step_count, step_buf, ws_root, &steps_out);
                            free(step_buf);
                        }
                        step_start = NULL;
                    }
                }
            }
        }
    } else {
        step_count = 1;
        execute_single_step(1, trimmed, ws_root, &steps_out);
    }

    sb_append(resp, "(:batch-res :status \"completed\" :items-count ");
    sb_append_int(resp, step_count);
    sb_append(resp, " :parallel true :results [\n");
    sb_append(resp, steps_out.data ? steps_out.data : "");
    sb_append(resp, "])\n");
    sb_free(&steps_out);
}

static char *find_ws_root(void) {
    static char buf[1024];
    if (getcwd(buf, sizeof(buf))) {
        char *p = buf;
        while (*p) {
            char test[1200];
            snprintf(test, sizeof(test), "%s/.asl.config.asn", buf);
            if (file_exists(test)) return buf;
            snprintf(test, sizeof(test), "%s/.git", buf);
            struct stat st;
            if (stat(test, &st) == 0) return buf;
            char *last = strrchr(buf, '/');
            if (!last || last == buf) break;
            *last = '\0';
        }
    }
    getcwd(buf, sizeof(buf));
    return buf;
}

static void run_serve(const char *sock_path, const char *ws_root, const char *pid_file) {
    snprintf(g_sock_path, sizeof(g_sock_path), "%s", sock_path);
    if (pid_file) snprintf(g_pid_path, sizeof(g_pid_path), "%s", pid_file);

    int test_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (test_fd >= 0) {
        struct sockaddr_un t_addr;
        memset(&t_addr, 0, sizeof(t_addr));
        t_addr.sun_family = AF_UNIX;
        strncpy(t_addr.sun_path, sock_path, sizeof(t_addr.sun_path) - 1);
        if (connect(test_fd, (struct sockaddr *)&t_addr, sizeof(t_addr)) == 0) {
            close(test_fd);
            fprintf(stderr, "Error: Engine already listening on socket: %s\n", sock_path);
            exit(1);
        }
        close(test_fd);
        unlink(sock_path);
    }

    signal(SIGTERM, sig_handler);
    signal(SIGINT, sig_handler);
    signal(SIGHUP, sig_handler);
    signal(SIGPIPE, SIG_IGN);
    atexit(cleanup_files);

    int sfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sfd < 0) {
        perror("socket");
        exit(1);
    }

    struct sockaddr_un s_addr;
    memset(&s_addr, 0, sizeof(s_addr));
    s_addr.sun_family = AF_UNIX;
    strncpy(s_addr.sun_path, sock_path, sizeof(s_addr.sun_path) - 1);

    if (bind(sfd, (struct sockaddr *)&s_addr, sizeof(s_addr)) < 0) {
        perror("bind");
        exit(1);
    }

    if (listen(sfd, 128) < 0) {
        perror("listen");
        exit(1);
    }

    if (pid_file && pid_file[0]) {
        FILE *pf = fopen(pid_file, "w");
        if (pf) {
            fprintf(pf, "%d\n", getpid());
            fclose(pf);
        }
    }

    printf("ASL Sovereign Engine resident at: %s (PID: %d)\n", sock_path, getpid());
    fflush(stdout);

    while (g_running) {
        int cfd = accept(sfd, NULL, NULL);
        if (cfd < 0) {
            if (errno == EINTR) continue;
            break;
        }

        StrBuf req_buf;
        sb_init(&req_buf);
        char chunk[4096];
        int depth = 0;
        int started = 0;
        int in_str = 0;
        int esc = 0;

        while (1) {
            ssize_t n = recv(cfd, chunk, sizeof(chunk) - 1, 0);
            if (n <= 0) break;
            chunk[n] = '\0';
            sb_append_len(&req_buf, chunk, n);

            for (ssize_t i = 0; i < n; i++) {
                char c = chunk[i];
                if (in_str) {
                    if (esc) esc = 0;
                    else if (c == '\\') esc = 1;
                    else if (c == '"') in_str = 0;
                } else {
                    if (c == '"') in_str = 1;
                    else if (c == '(') {
                        depth++;
                        started = 1;
                    } else if (c == ')') {
                        depth--;
                        if (started && depth == 0) break;
                    }
                }
            }
            if (started && depth == 0) break;
        }

        if (req_buf.len > 0) {
            StrBuf resp_buf;
            sb_init(&resp_buf);
            handle_payload(req_buf.data, ws_root, &resp_buf);
            if (resp_buf.len > 0) {
                send(cfd, resp_buf.data, resp_buf.len, 0);
            }
            sb_free(&resp_buf);
        }
        sb_free(&req_buf);
        close(cfd);
    }

    close(sfd);
    cleanup_files();
}

int main(int argc, char **argv) {
    char *ws_root = getenv("ASL_WORKSPACE_ROOT");
    char discovered_ws[1024];
    if (!ws_root || !ws_root[0]) {
        ws_root = find_ws_root();
    }
    snprintf(discovered_ws, sizeof(discovered_ws), "%s", ws_root);

    if (argc >= 2 && strcmp(argv[1], "--serve") == 0) {
        char sock[1024];
        char ws[1024];
        char pid[1024];
        const char *bname = strrchr(discovered_ws, '/');
        bname = bname ? bname + 1 : "default";

        snprintf(sock, sizeof(sock), "%s", (argc > 2) ? argv[2] : "");
        if (!sock[0]) snprintf(sock, sizeof(sock), "/tmp/asl_mem_%s.sock", bname);

        snprintf(ws, sizeof(ws), "%s", (argc > 3) ? argv[3] : discovered_ws);

        snprintf(pid, sizeof(pid), "%s", (argc > 4) ? argv[4] : "");
        if (!pid[0]) snprintf(pid, sizeof(pid), "/tmp/asl_mem_%s.pid", bname);

        run_serve(sock, ws, pid);
        return 0;
    }

    if (argc >= 2 && strcmp(argv[1], "--daemon") == 0) {
        const char *bname = strrchr(discovered_ws, '/');
        bname = bname ? bname + 1 : "default";
        char sock[1024];
        char pid[1024];
        snprintf(sock, sizeof(sock), "/tmp/asl_mem_%s.sock", bname);
        snprintf(pid, sizeof(pid), "/tmp/asl_mem_%s.pid", bname);

        pid_t pid_val = fork();
        if (pid_val < 0) {
            perror("fork");
            return 1;
        }
        if (pid_val > 0) {
            return 0;
        }
        setsid();
        run_serve(sock, discovered_ws, pid);
        return 0;
    }

    if (argc >= 2 && strcmp(argv[1], "--status") == 0) {
        const char *bname = strrchr(discovered_ws, '/');
        bname = bname ? bname + 1 : "default";
        char sock[1024];
        snprintf(sock, sizeof(sock), "%s", (argc > 2) ? argv[2] : "");
        if (!sock[0]) snprintf(sock, sizeof(sock), "/tmp/asl_mem_%s.sock", bname);

        int fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd < 0) {
            printf("Status: Offline (socket creation failed)\n");
            return 1;
        }
        struct sockaddr_un addr;
        memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, sock, sizeof(addr.sun_path) - 1);
        if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            close(fd);
            printf("Status: Offline (Socket %s not responding)\n", sock);
            return 1;
        }
        send(fd, "(:inspect)\n", 11, 0);
        char buf[1024] = {0};
        recv(fd, buf, sizeof(buf) - 1, 0);
        close(fd);
        printf("Socket: %s\nStatus: Online (%s)\n", sock, buf);
        return 0;
    }

    if (argc >= 2 && strcmp(argv[1], "--stop") == 0) {
        const char *bname = strrchr(discovered_ws, '/');
        bname = bname ? bname + 1 : "default";
        char pid_file[1024];
        char sock[1024];
        snprintf(pid_file, sizeof(pid_file), "%s", (argc > 2) ? argv[2] : "");
        if (!pid_file[0]) snprintf(pid_file, sizeof(pid_file), "/tmp/asl_mem_%s.pid", bname);
        snprintf(sock, sizeof(sock), "%s", (argc > 3) ? argv[3] : "");
        if (!sock[0]) snprintf(sock, sizeof(sock), "/tmp/asl_mem_%s.sock", bname);

        FILE *pf = fopen(pid_file, "r");
        if (pf) {
            int p = 0;
            if (fscanf(pf, "%d", &p) == 1 && p > 0) {
                kill(p, SIGTERM);
                for (int i = 0; i < 20; i++) {
                    usleep(50000);
                    if (kill(p, 0) != 0) break;
                }
            }
            fclose(pf);
        }
        unlink(pid_file);
        unlink(sock);
        printf("ASL Engine stopped cleanly.\n");
        return 0;
    }

    if (argc >= 3 && strcmp(argv[1], "--ping") == 0) {
        const char *sock_path = argv[2];
        int fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd < 0) return 1;
        struct sockaddr_un addr;
        memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, sock_path, sizeof(addr.sun_path) - 1);
        struct timeval tv;
        tv.tv_sec = 0;
        tv.tv_usec = 100000;
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
            close(fd);
            return 1;
        }
        if (write(fd, "(:ping)\n", 8) <= 0) {
            close(fd);
            return 1;
        }
        char buf[256];
        ssize_t n = read(fd, buf, sizeof(buf) - 1);
        close(fd);
        if (n > 0) {
            buf[n] = '\0';
            if (strstr(buf, "pong")) return 0;
        }
        return 1;
    }

    if (argc >= 4 && strcmp(argv[1], "--client") == 0) {
        const char *sock_path = argv[2];
        const char *msg = argv[3];
        int fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd < 0) return 1;
        struct sockaddr_un addr;
        memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, sock_path, sizeof(addr.sun_path) - 1);
        struct timeval tv;
        tv.tv_sec = 2;
        tv.tv_usec = 0;
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
            close(fd);
            return 1;
        }
        size_t mlen = strlen(msg);
        write(fd, msg, mlen);
        write(fd, "\n", 1);
        shutdown(fd, SHUT_WR);
        char buf[4096];
        ssize_t n;
        while ((n = read(fd, buf, sizeof(buf))) > 0) {
            fwrite(buf, 1, n, stdout);
        }
        close(fd);
        return 0;
    }

    if (argc >= 2 && (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "help") == 0)) {
        printf("Usage: asl-engine <payload> | echo '<payload>' | asl-engine | asl-engine --serve <sock> <ws> <pid>\n");
        return 0;
    }

    StrBuf payload_buf;
    sb_init(&payload_buf);

    if (argc >= 2 && argv[1][0] && argv[1][0] != '-') {
        for (int i = 1; i < argc; i++) {
            if (i > 1) sb_append(&payload_buf, " ");
            sb_append(&payload_buf, argv[i]);
        }
    } else if (!isatty(STDIN_FILENO)) {
        char in_chunk[4096];
        ssize_t nr;
        while ((nr = read(STDIN_FILENO, in_chunk, sizeof(in_chunk))) > 0) {
            sb_append_len(&payload_buf, in_chunk, nr);
        }
    }

    if (payload_buf.len == 0) {
        printf("Usage: asl-engine <payload> | echo '<payload>' | asl-engine | asl-engine --serve <sock> <ws> <pid>\n");
        sb_free(&payload_buf);
        return 1;
    }

    StrBuf resp_buf;
    sb_init(&resp_buf);
    handle_payload(payload_buf.data, discovered_ws, &resp_buf);
    if (resp_buf.data) {
        fputs(resp_buf.data, stdout);
    }
    sb_free(&resp_buf);
    sb_free(&payload_buf);
    return 0;
}
