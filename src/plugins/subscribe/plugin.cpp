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

internal const char *SockPath = "/tmp/chunkwm-subscribe";
int sockfd;
pthread_t accept_thread_id;

typedef struct _fdsnode {
    int id;
    int fds[2];
    struct _fdsnode *next;
} fdsnode;

fdsnode *fdlist = NULL;

chunkwm_log *c_log;

fdsnode*
AppendNode(int id)
{
    fdsnode *curfd;
    fdsnode *newnode = (fdsnode*) malloc(sizeof(fdsnode));
    newnode->id = id;
    if (pipe(newnode->fds) == -1) {
        c_log(C_LOG_LEVEL_ERROR, "Failed to create message pipes\n");
        return NULL;
    }
    newnode->next = NULL;
    if (fdlist) {
        curfd = fdlist;
        while (curfd->next) curfd = curfd->next;
        curfd->next = newnode;
    } else {
        fdlist = newnode;
    }
    return newnode;
}


int
DeleteNode(int id)
{
    fdsnode *prevfd = NULL;
    fdsnode *curfd = fdlist;
    while (curfd) {
        if (curfd->id == id) {
            if (prevfd) prevfd->next = curfd->next;
            else fdlist = curfd->next;
            close(curfd->fds[0]);
            close(curfd->fds[1]);
            free(curfd);
            return 0;
        }
        prevfd = curfd;
        curfd = curfd->next;
    }
    return -1;
}


void*
HandleConnection(void* arg)
{
    fdsnode *cur = (fdsnode*)arg;

    struct pollfd fds[2];

    char buffer[1024];
    ssize_t received;

    fds[0] = {cur->fds[0], POLLIN | POLLPRI, 0};
    fds[1] = {cur->id, POLLIN | POLLPRI, 0};

    int rbytes;
    int offset = 0;
    printf("Handling pipes %d %d\n", cur->id, cur->fds[0]);
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
        offset = 0;
        memset(buffer, 0, 1024);
    }
    if (close(cur->id) == -1) {
        c_log(C_LOG_LEVEL_ERROR, "Failed to handle client\n");
    }
    DeleteNode(cur->id);
    return NULL;
}

void*
AcceptConnections(void* arg)
{
    int sockfd = *(int*)arg;
    int client_sock;
    fdsnode *args;
    while (true) {
        pthread_t pthread_id;
        if ((client_sock = accept(sockfd, NULL, NULL)) == -1) {
            c_log(C_LOG_LEVEL_ERROR, "Failed to accept client\n");
            continue;
        }
        args = AppendNode(client_sock);
        pthread_create(&pthread_id, NULL, HandleConnection, (void*) args);
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
    snprintf(log_message, 254, "%s\n", Node);
    fdsnode *curnode = fdlist;
    while (curnode != NULL) {
        write(curnode->fds[1], log_message, strlen(log_message));
        curnode = curnode->next;
    }
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

    fdsnode *prevnode = NULL;
    fdsnode *curnode = fdlist;
    while (curnode) {
        prevnode = curnode;
        curnode = curnode->next;
        free(prevnode);
    }
    free(curnode);
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
