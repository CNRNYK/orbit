// Keep one controlling terminal for the reviewed Homebrew queue. Homebrew itself
// remains unprivileged. The terminal is never used to receive a password.
#include <errno.h>
#include <fcntl.h>
#include <util.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <unistd.h>

static int frame(uint32_t type, int32_t value, const void *bytes) {
    uint32_t header[] = {type, (uint32_t)value};
    return fwrite(header, sizeof header, 1, stdout) == 1 &&
        (!bytes || fwrite(bytes, 1, (size_t)value, stdout) == (size_t)value) &&
        fflush(stdout) == 0;
}
static int wait_status(pid_t pid) {
    int status;
    while (waitpid(pid, &status, 0) < 0) if (errno != EINTR) return 125;
    return WIFEXITED(status) ? WEXITSTATUS(status) : 125;
}
static int token_ok(const char *token) {
    const char *allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@+._-/";
    return token[0] && token[0] != '-' && token[0] != '/' &&
        strspn(token, allowed) == strlen(token);
}
static int queue(const char *brew) {
    if (!frame(0, 0, NULL)) return 125;
    char line[512];
    while (fgets(line, sizeof line, stdin)) {
        char *end = strchr(line, '\n');
        if (!end) return 125;
        *end = '\0';
        if ((line[0] != 'c' && line[0] != 'f') || line[1] != '\t' || !token_ok(line+2)) return 125;
        int stream[2];
        if (pipe(stream) != 0) return 125;
        pid_t pid = fork();
        if (pid == 0) {
            close(stream[0]);
            if (dup2(stream[1], STDOUT_FILENO) < 0 || dup2(stream[1], STDERR_FILENO) < 0) _exit(125);
            close(stream[1]);
            if (!freopen("/dev/null","r",stdin)) _exit(125);
            if (line[0] == 'c') execl(brew,brew,"upgrade","--cask","--greedy-auto-updates",line+2,(char *)NULL);
            else execl(brew,brew,"upgrade","--formula",line+2,(char *)NULL);
            _exit(127);
        }
        close(stream[1]);
        if (pid < 0) { close(stream[0]); return 125; }
        char buffer[4096];
        ssize_t n;
        do {
            n = read(stream[0],buffer,sizeof buffer);
            if (n > 0 && !frame(1,(int32_t)n,buffer)) { close(stream[0]); return 125; }
        } while (n > 0 || (n < 0 && errno == EINTR));
        close(stream[0]);
        if (!frame(2,wait_status(pid),NULL)) return 125;
    }
    return 0;
}
int main(int argc, char **argv) {
    if (argc != 2) return 125;
#ifndef ORBIT_SESSION_TEST
    if (strcmp(argv[1],"/opt/homebrew/bin/brew") && strcmp(argv[1],"/usr/local/bin/brew")) return 125;
#endif
    int master, slave;
    if (openpty(&master,&slave,NULL,NULL,NULL) != 0) return 125;
    pid_t worker = fork();
    if (worker == 0) {
        close(master);
        if (setsid() < 0 || ioctl(slave,TIOCSCTTY,0) < 0) _exit(125);
        if (fcntl(slave,F_SETFD,FD_CLOEXEC) < 0) _exit(125);
        int result = queue(argv[1]);
        close(slave);
        _exit(result);
    }
    close(slave);
    if (worker < 0) { close(master); return 125; }
    // Drain terminal-only messages without logging them. Commands use the framed pipe.
    char drain[4096];
    ssize_t n;
    do { n = read(master,drain,sizeof drain); } while (n > 0 || (n < 0 && errno == EINTR));
    close(master);
    return wait_status(worker);
}
