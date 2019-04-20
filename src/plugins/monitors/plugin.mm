#include <stdlib.h>
#include <string.h>
#include <vector>
#include <string>
#include <sstream>

#include "../../api/plugin_api.h"
#include "../../common/accessibility/display.h"
#include "../../common/config/cvar.h"
#include "../../common/ipc/daemon.h"

#include "../../common/accessibility/display.mm"
#include "../../common/accessibility/element.cpp"
#include "../../common/config/cvar.cpp"
#include "../../common/ipc/daemon.cpp"

#define internal static

internal const char *PluginName = "monitors";
internal const char *PluginVersion = "0.1.0";
internal chunkwm_api API;
chunkwm_log *c_log;

#define MAX_DESKTOP
std::vector<unsigned> DesktopCounts;

void
BroadcastDesktopRefresh()
{
    API.Broadcast(PluginName, "spaces_set", 0, 0);
}

void
SetDesktopCounts(const char *definition)
{
    std::string input(definition);
    std::stringstream stream(input);
    int n;
    DesktopCounts.clear();
    while (stream >> n) {
        DesktopCounts.push_back(n);
    }
}

int
ArrangementToCount(unsigned arrangement)
{
    int count;
    try {
        count = DesktopCounts.at(arrangement);
    } catch (const std::out_of_range &e) {
        count = -1;
    }
    return count;
}

void
CreateDesktop(macos_display *Display)
{
    macos_space *Space = AXLibActiveSpace(Display->Ref);
    if (!Space) return;

    int SockFD;

    c_log(C_LOG_LEVEL_DEBUG, "Create space for display %d\n", Display->Arrangement);
    if (ConnectToDaemon(&SockFD, 5050)) {
        char Message[64];
        sprintf(Message, "space_create %d", Space->Id);
        WriteToSocket(Message, SockFD);
    }
    CloseSocket(SockFD);
    usleep(100 * 1000);

    AXLibDestroySpace(Space);
}

void
DeleteDesktop(macos_display *Display)
{
    macos_space *Space = AXLibActiveSpace(Display->Ref);
    if (!Space) return;
    if (Space->Type != kCGSSpaceUser) goto free_spaces;

    int SockFD;
    c_log(C_LOG_LEVEL_DEBUG, "Delete space for display %d\n", Display->Arrangement);
    if (ConnectToDaemon(&SockFD, 5050)) {
        char Message[64];
        sprintf(Message, "space_destroy %d", Space->Id);
        WriteToSocket(Message, SockFD);
    }
    CloseSocket(SockFD);
    /* Slow delete to make sure desktops are deleted */
    usleep(100 * 1000);

free_spaces:
    AXLibDestroySpace(Space);
}

inline int
MonitorSpacesCount(macos_display *Display)
{
    int count, *spaces;
    spaces = AXLibSpacesForDisplay(Display->Ref, &count);
    free(spaces);
    return count;
}

inline bool
SetMonitorDesktops(macos_display *Display)
{
    int count, *spaces;
    spaces = AXLibSpacesForDisplay(Display->Ref, &count);
    int wanted = ArrangementToCount(Display->Arrangement);
    if (wanted > 0) {
        while (count < wanted) {
            CreateDesktop(Display);
            count++;
        }
        while (count > wanted) {
            DeleteDesktop(Display);
            count--;
        }
    }
    free(spaces);
    return wanted == MonitorSpacesCount(Display);
}

inline bool
SetMonitors()
{
    bool Success = true;
    unsigned count;
    macos_display *Display, **Displays;
    Displays = AXLibDisplayList(&count);
    for (int i = 0; i < count; i++) {
        Display = Displays[i];
        if (!SetMonitorDesktops(Display)) Success = false;
        AXLibDestroyDisplay(Display);
    }
    free(Displays);
    if (Success) {
        BroadcastDesktopRefresh();
    }
    return Success;
}

inline bool
DaemonCommandHandler(void *Data)
{
    chunkwm_payload *Payload = (chunkwm_payload *) Data;
    if (strcmp(Payload->Command, "refresh") == 0) {
        if (SetMonitors()) {
            WriteToSocket("Monitor spaces set successful.", Payload->SockFD);
        } else {
            WriteToSocket("Monitor spaces set failed.", Payload->SockFD);
        }
    } else {
        WriteToSocket("Unknown command to monitors", Payload->SockFD);
    };
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
    if (strcmp(Node, "chunkwm_export_display_added") == 0) {
        return SetMonitors();
    } else if (strcmp(Node, "chunkwm_export_display_removed") == 0) {
        return SetMonitors();
    } else if (strcmp(Node, "chunkwm_export_space_changed") == 0) {
        // return SpaceChanged();
    } else if (strcmp(Node, "chunkwm_daemon_command") == 0) {
        return DaemonCommandHandler(Data);
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

    BeginCVars(&API);
    CreateCVar("monitors_arrangement", "3 4 4");
    SetDesktopCounts(CVarStringValue("monitors_arrangement"));

    SetMonitors();
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
