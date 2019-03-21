#include <stdlib.h>
#include <string.h>

#include <sys/socket.h>
#include <sys/un.h>

#include <poll.h>

#include <pthread.h>

#include "../../api/plugin_api.h"
#include "../../common/accessibility/application.h"
#include "../../common/accessibility/window.h"

#define internal static

internal const char *PluginName = "subscribe";
internal const char *PluginVersion = "0.1.0";
internal chunkwm_api API;

internal const char *SockPath = "socket";
int sockfd;
pthread_t accept_thread_id;

int msgfds[2];

chunkwm_log *c_log;

void*
HandleConnection(void* arg)
{
    int socket = *(int*)arg;

    struct pollfd fds[2];

    char buffer[1024];
    ssize_t received;

    fds[0] = {msgfds[0], POLLIN | POLLPRI, 0};
    fds[1] = {socket, POLLIN | POLLPRI, 0};

    int rbytes;
    int offset = 0;
    while (true) {
        if (poll(fds, 2, -1) < 1) {
            c_log(C_LOG_LEVEL_ERROR, "Poll failed\n");
            break;
        }
        // Handle Pipe input
        if (fds[0].revents & (POLLIN|POLLPRI)) {
            while ((rbytes = read(fds[0].fd, buffer + offset, 1023)) > 0) {
                offset += rbytes;
                break;
            }
            if (offset > 0) {
                send(fds[1].fd, buffer, strlen(buffer), 0);
            }
        }
        // Handle Client Socket Input, currently only closing connection
        if (fds[1].revents & (POLLIN|POLLPRI)) {
            if ((received = recv(fds[1].fd, buffer, 1023, 0)) < 1) {
                c_log(C_LOG_LEVEL_WARN, "Connection to client closed\n");
                break;
            }
        }
    }
    if (close(socket) == -1) {
        c_log(C_LOG_LEVEL_ERROR, "Failed to handle client\n");
    }
    return NULL;
}

void*
AcceptConnections(void* arg)
{
    int sockfd = *(int*)arg;
    int client_sockfd;
    while (true) {
        pthread_t pthread_id;
        if ((client_sockfd = accept(sockfd, NULL, NULL)) == -1) {
            c_log(C_LOG_LEVEL_ERROR, "Failed to accept client\n");
            continue;
        }
        pthread_create(&pthread_id, NULL, HandleConnection, (void*) &client_sockfd);
        // close(client_sockfd);
    }
    return NULL;
}

inline bool
StringsAreEqual(const char *A, const char *B)
{
    bool Result = (strcmp(A, B) == 0);
    return Result;
}

/*
 * NOTE(koekeishiya):
 * parameter: const char *Node
 * parameter: void *Data
 * return: bool
 */
PLUGIN_MAIN_FUNC(PluginMain)
{
    char log_message[256];
    snprintf(log_message, 255, "%s\n", Node);
    write(msgfds[1], log_message, strlen(log_message));
    return false;
}

/*
 * NOTE(koekeishiya):
 * parameter: chunkwm_api ChunkwmAPI
 * return: bool -> true if startup succeeded
 */
PLUGIN_BOOL_FUNC(PluginInit)
{
    API = ChunkwmAPI;
    c_log = API.Log;

    if (pipe(msgfds) == -1) {
        c_log(C_LOG_LEVEL_ERROR, "Failed to create message pipes\n");
        return false;
    }

    if ((sockfd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
        c_log(C_LOG_LEVEL_ERROR, "Failed to create socket\n");
        return false;
    }

    unlink(SockPath);

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SockPath, sizeof(addr.sun_path)-1);
    if ((bind(sockfd, (struct sockaddr*)&addr, sizeof(addr))) == -1) {
        c_log(C_LOG_LEVEL_ERROR, "Failed to bind socket to unix domain\n");
        return false;
    }

    if (listen(sockfd, 10) == -1) {
        c_log(C_LOG_LEVEL_ERROR, "Failed to listen\n");
        return false;
    }
    pthread_create(&accept_thread_id, NULL, AcceptConnections, (void*) &sockfd);

    return true;
}

PLUGIN_VOID_FUNC(PluginDeInit)
{
    close(sockfd);
    unlink(SockPath);
}

// NOTE(koekeishiya): Enable to manually trigger ABI mismatch
#if 0
#undef CHUNKWM_PLUGIN_API_VERSION
#define CHUNKWM_PLUGIN_API_VERSION 0
#endif

// NOTE(koekeishiya): Initialize plugin function pointers.
CHUNKWM_PLUGIN_VTABLE(PluginInit, PluginDeInit, PluginMain)

// NOTE(koekeishiya): Subscribe to ChunkWM events!
chunkwm_plugin_export Subscriptions[] =
{
    chunkwm_export_space_changed,
    chunkwm_export_display_changed,

    chunkwm_export_display_added,
    chunkwm_export_display_removed,
    chunkwm_export_display_moved,
};
CHUNKWM_PLUGIN_SUBSCRIBE(Subscriptions)

// NOTE(koekeishiya): Generate plugin
CHUNKWM_PLUGIN(PluginName, PluginVersion);
