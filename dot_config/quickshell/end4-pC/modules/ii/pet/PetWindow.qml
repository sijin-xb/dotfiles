pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * The desktop pet: a tiny shell-native creature in the bottom-right corner.
 * Its mood comes from real system state (see PetState). It is NOT a
 * standalone desktop-pet app — it lives inside the shell, follows the
 * matugen palette, and never gets in the way: only its body takes input.
 *
 * IPC:
 *   qs -c end4-pC ipc call pet toggle|show|hide|status
 *   qs -c end4-pC ipc call pet mood busy    (force a mood; "auto" releases)
 */
PanelWindow {
    id: root

    property bool petEnabled: true

    WlrLayershell.namespace: "quickshell:pet"
    WlrLayershell.layer: WlrLayer.Top
    exclusiveZone: -1
    color: "transparent"
    visible: root.petEnabled

    anchors {
        bottom: true
        right: true
    }
    margins {
        bottom: 12
        right: 12
    }
    // Anchored children do not contribute implicit sizes: the window needs an
    // explicit size, otherwise it collapses to 0 and stays invisible
    implicitWidth: 220
    implicitHeight: 250

    // Only the creature's bounding box takes input; the rest clicks through
    mask: Region {
        item: petContent.interactionRoot
    }

    PetState {
        id: petState
        active: root.petEnabled
    }

    Pet {
        id: petContent
        anchors.fill: parent
        vitals: petState
    }

    IpcHandler {
        target: "pet"

        function toggle(): void {
            root.petEnabled = !root.petEnabled;
        }
        function show(): void {
            root.petEnabled = true;
        }
        function hide(): void {
            root.petEnabled = false;
        }
        function mood(mood: string): void {
            petState.moodOverride = mood;
        }
        function status(): string {
            return petState.mood;
        }
    }
}
