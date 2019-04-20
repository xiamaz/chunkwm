#include <stdlib.h>
#include <string.h>

#include "../../api/plugin_api.h"
#include "../../common/accessibility/display.h"
#include "../../common/ipc/daemon.h"

#include "../../common/accessibility/display.mm"
#include "../../common/accessibility/element.cpp"
#include "../../common/ipc/daemon.cpp"

#define internal static

internal const char *PluginName = "monitors";
internal const char *PluginVersion = "0.1.0";
internal chunkwm_api API;
chunkwm_log *c_log;

void
CreateDesktop(macos_space *Space)
{
    int SockFD;

    if (ConnectToDaemon(&SockFD, 5050)) {
        char Message[64];
        sprintf(Message, "space_create %d", Space->Id);
        WriteToSocket(Message, SockFD);
    }
    CloseSocket(SockFD);
}

void
DeleteDesktop()
{
    macos_space *Space;
    if (!AXLibActiveSpace(&Space)) {
        c_log(C_LOG_LEVEL_WARN, "Failed to get current space\n");
    }

    int SockFD;

    c_log(C_LOG_LEVEL_WARN, "Delete space\n");
    if (ConnectToDaemon(&SockFD, 5050)) {
        char Message[64];
        sprintf(Message, "space_destroy %d", Space->Id);
        WriteToSocket(Message, SockFD);
    }
    CloseSocket(SockFD);
}

unsigned
GetCurrentSpaces(CFStringRef MonitorRef, macos_space **Space)
{
    macos_space *CurSpace, **List, **Spaces;
    List = Spaces = AXLibSpacesForDisplay(MonitorRef);
	unsigned count = 0;
    while ((CurSpace = *List++)) {
        if (!count) {
            *Space = CurSpace;
        } else {
            AXLibDestroySpace(CurSpace);
        }
        count++;
    }
    free(Spaces);
    return count;
}

void
CreateMonitorSpaces(CFStringRef MonitorRef, unsigned count)
{
    macos_space *Space, *LastSpace, **List, **Spaces;
    List = Spaces = AXLibSpacesForDisplay(MonitorRef);
	unsigned current = 0;
    while ((Space = *List++)) {
        LastSpace = Space;
        current++;
    }
    c_log(C_LOG_LEVEL_WARN, "M %d/%d\n", current, count);
    if (current < count) {
        while (current < count) {
            CreateDesktop(LastSpace);
            current++;
        }
    } else {
        current = 0;
        List = Spaces;
        while ((Space = *List++)) {
            if (current >= count) DeleteDesktop();
            current++;
        }
    }

    List = Spaces;
    while ((Space = *List++)) {
        AXLibDestroySpace(Space);
    }
    free(Spaces);
}

void
MonitorSpaces(CFStringRef MonitorRef)
{
    macos_space *Space, **List, **Spaces;
    List = Spaces = AXLibSpacesForDisplay(MonitorRef);
    c_log(C_LOG_LEVEL_WARN, "M %s:\n",
          CFStringGetCStringPtr(MonitorRef, kCFStringEncodingUTF8));
    while ((Space = *List++)) {
        c_log(C_LOG_LEVEL_WARN, "Space\n");
        AXLibDestroySpace(Space);
    }
    c_log(C_LOG_LEVEL_WARN, "END\n");
    free(Spaces);
}

inline bool
SpaceChanged()
{
    macos_space *Space;
    if (!AXLibActiveSpace(&Space)) {
        c_log(C_LOG_LEVEL_WARN, "Failed to get current space\n");
        return false;
    }
    CFStringRef MonitorRef = AXLibGetDisplayIdentifierFromSpace(Space->Id);
    if (!MonitorRef) {
        c_log(C_LOG_LEVEL_WARN, "Failed to get current monitor\n");
        goto free_spaces;
    }
    MonitorSpaces(MonitorRef);
    CreateMonitorSpaces(MonitorRef, 3);
free_spaces:
    AXLibDestroySpace(Space);
    return false;
}

inline bool
MonitorChanged(uint32_t MonitorId)
{
    CFStringRef MonitorRef = AXLibGetDisplayIdentifier(MonitorId);
    c_log(C_LOG_LEVEL_WARN,
          "Monitor changed %s\n",
          CFStringGetCStringPtr(MonitorRef, kCFStringEncodingUTF8));
    return false;
}

/*
 * NOTE(koekeishiya):
 * parameter: const char *Node
 * parameter: void *Data
 * return: bool
 */
PLUGIN_MAIN_FUNC(PluginMain)
{
    if (strcmp(Node, "chunkwm_export_space_changed") == 0) {
        return SpaceChanged();
    } else if (strcmp(Node, "chunkwm_export_display_added") == 0) {
        return MonitorChanged(*(uint32_t*)Data);
    } else if (strcmp(Node, "chunkwm_export_display_removed") == 0) {
        return MonitorChanged(*(uint32_t*)Data);
    } else {
        c_log(C_LOG_LEVEL_WARN, "Unknown node type: %s\n", Node);
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
    return true;
}

PLUGIN_VOID_FUNC(PluginDeInit)
{
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
    chunkwm_export_display_added,
    chunkwm_export_display_removed,
};
CHUNKWM_PLUGIN_SUBSCRIBE(Subscriptions)

// NOTE(koekeishiya): Generate plugin
CHUNKWM_PLUGIN(PluginName, PluginVersion);
