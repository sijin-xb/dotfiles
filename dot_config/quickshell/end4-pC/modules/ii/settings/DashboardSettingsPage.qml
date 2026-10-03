import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    required property Item pager
    property int staggerMs: 45
    readonly property string query: pager.searchQuery ?? ""

    readonly property real rowHeight: 140
    readonly property real headerHeight: 36
    readonly property real gap: 12

    readonly property var shapePool: [
        MaterialShape.Shape.Cookie6Sided, MaterialShape.Shape.Gem, MaterialShape.Shape.Pentagon,
        MaterialShape.Shape.Flower, MaterialShape.Shape.Puffy, MaterialShape.Shape.Clover8Leaf, MaterialShape.Shape.Sunny
    ]

    DashboardSettingsCatalog {
        id: catalog
    }

    function spanOf(entry) {
        return entry.w ? [entry.w, 1] : baseSpan(entry.type);
    }

    function baseSpan(type) {
        if (type === "style") return [2, 2];
        if (type === "schemes" || type === "barpos") return [2, 2];
        if (type === "weathermap") return [4, 2];
        if (type === "shape") return [2, 2];
        if (type === "barlayout") return [4, 3];
        if (type === "palette") return [4, 1];
        if (type === "iconpicker") return [2, 2];
        if (type === "toggle" || type === "spin") return [1, 1];
        return [2, 1];
    }

    readonly property var heroEntries: [
        { id: "hero:style", type: "style", title: Translation.tr("Settings panel style"), section: Translation.tr("Interface"), kw: "settings panel style default minimal dashboard window overlay" },
        { id: "hero:blur", type: "toggle", key: "desktop:Blur wall", title: Translation.tr("Blur wallpaper"), icon: "blur_on", section: Translation.tr("Desktop"), kw: "blur wallpaper background" },
        { id: "hero:transparency", type: "toggle", key: "interface:Transparency/Enable", title: Translation.tr("Transparency"), icon: "opacity", section: Translation.tr("Interface"), kw: "transparency opacity" },
        { id: "hero:collage", type: "toggle", key: "desktop:Collage enable", title: Translation.tr("Multiple wallpapers"), icon: "grid_view", section: Translation.tr("Desktop"), kw: "multiple wallpapers collage tiles" },
        { id: "hero:centered", type: "toggle", key: "desktop:Wallpaper/Centered wallpaper/Enable", title: Translation.tr("Centered wallpaper"), icon: "filter_center_focus", section: Translation.tr("Desktop"), kw: "centered wallpaper" },
        { id: "hero:schemes", type: "schemes", title: Translation.tr("Color scheme"), section: Translation.tr("Interface"), kw: "color scheme theme palette accent catppuccin gruvbox nord dracula tokyo everforest one dark" },
        { id: "hero:palette", type: "palette", when: "material", key: "interface:Palette type", title: Translation.tr("Palette style"), icon: "auto_awesome", section: Translation.tr("Interface"), kw: "palette style scheme auto content expressive fidelity fruit salad monochrome neutral rainbow tonal spot material you dynamic" },
        { id: "hero:barpos", type: "barpos", title: Translation.tr("Bar position"), section: Translation.tr("Bar"), kw: "bar position top bottom left right vertical panel" }
    ]

    readonly property var allEntries: {
        const list = [];
        heroEntries.forEach(e => list.push(Object.assign({ kind: "card", hero: true }, e)));
        catalog.sections.forEach((section, si) => {
            list.push({ id: "section:" + si, kind: "header", requires: section.requires ?? "", when: section.when ?? "", title: section.title, icon: section.icon, page: section.page ?? "", section: section.title, sectionIndex: si, count: section.cards.length });
            section.cards.forEach(card => list.push(Object.assign({
                id: card.key, kind: "card", requires: section.requires ?? "", when: section.when ?? "", section: section.title, sectionIndex: si, kw: card.kw ?? ""
            }, card)));
        });
        const heroGroups = {};
        heroEntries.forEach(e => { heroGroups[e.section] = (heroGroups[e.section] ?? 0) + 1; });
        Object.keys(heroGroups).forEach(name => list.push({
            id: "hsection:" + name, kind: "header", searchOnly: true, requires: "",
            title: name, icon: name === "Desktop" ? "texture" : name === "Bar" ? "toast" : "bottom_app_bar",
            page: name, section: name, count: heroGroups[name]
        }));
        return list.map(e => Object.assign(e, {
            shape: shapePool[Math.floor(Math.random() * shapePool.length)],
            travelX: (Math.random() - 0.5) * 500,
            travelY: (Math.random() - 0.5) * 400
        }));
    }

    readonly property var usedWidgets: {
        const layouts = Config.options.bar.layouts;
        return Array.from(layouts.leftLayout).concat(Array.from(layouts.middleLayout), Array.from(layouts.rightLayout));
    }

    function isVisibleEntry(e) {
        if (e.when === "material" && ColorSchemes.current !== "") return false;
        if (e.when === "hyprland" && WM.compositor !== "hyprland") return false;
        return !e.requires || usedWidgets.includes(e.requires);
    }

    function normalized(text) {
        return Wallpapers.normalizeText(text).replace(/[_\-.:/]+/g, " ");
    }

    function matches(tokens) {
        const scored = [];
        allEntries.forEach(e => {
            if (e.kind !== "card" || (e.hero && e.type === "toggle") || !isVisibleEntry(e)) return;
            const key = normalized([e.title, e.section, e.kw, e.key ?? ""].join(" "));
            const score = Wallpapers.scoreItem(key, tokens);
            if (score >= 0) scored.push({ entry: e, score: score });
        });
        scored.sort((a, b) => b.score - a.score);
        return scored.map(s => s.entry);
    }

    function packRows(cards, capacity) {
        const fulls = cards.filter(c => spanOf(c)[0] === 4);
        const wides = cards.filter(c => spanOf(c)[0] === 2);
        const smalls = cards.filter(c => spanOf(c)[0] === 1);
        const placed = [];
        let remaining = capacity;
        let rowStart = 0;
        fulls.concat(wides, smalls).forEach(card => {
            const span = spanOf(card)[0];
            if (span > remaining) {
                remaining = capacity;
                rowStart = placed.length;
            }
            placed.push({ entry: card, w: span, h: spanOf(card)[1] });
            remaining -= span;
            if (remaining === 0) {
                remaining = capacity;
                rowStart = placed.length;
            }
        });
        let leftover = remaining === capacity ? 0 : remaining;
        let i = placed.length - 1;
        while (leftover > 0 && i >= rowStart) {
            placed[i].w += 1;
            leftover--;
            i = i === rowStart ? placed.length - 1 : i - 1;
        }
        return placed;
    }

    function computeLayout(tokens) {
        const items = [];
        if (tokens.length > 0) {
            const groups = {};
            const order = [];
            matches(tokens).forEach(e => {
                const groupId = e.sectionIndex !== undefined ? "section:" + e.sectionIndex : "hsection:" + e.section;
                if (!groups[groupId]) {
                    groups[groupId] = [];
                    order.push(groupId);
                }
                groups[groupId].push(e);
            });
            order.forEach(groupId => {
                const header = allEntries.find(e => e.id === groupId);
                if (header) items.push({ entry: header, w: 4, h: 1, header: true });
                packRows(groups[groupId], 4).forEach(p => items.push(p));
            });
        } else {
            let i = 0;
            while (i < allEntries.length) {
                const e = allEntries[i];
                if (e.searchOnly || !isVisibleEntry(e)) {
                    i++;
                    continue;
                }
                if (e.kind === "header") {
                    items.push({ entry: e, w: 4, h: 1, header: true });
                    const cards = [];
                    i++;
                    while (i < allEntries.length && allEntries[i].kind === "card") {
                        if (isVisibleEntry(allEntries[i])) cards.push(allEntries[i]);
                        i++;
                    }
                    packRows(cards, 4).forEach(p => items.push(p));
                } else {
                    const s = spanOf(e);
                    items.push({ entry: e, w: s[0], h: s[1] });
                    i++;
                }
            }
        }

        const occ = [];
        const rowH = [];
        const map = {};
        let floor = 0;

        function ensure(r) {
            while (occ.length <= r) {
                occ.push([false, false, false, false]);
                rowH.push(rowHeight);
            }
        }

        function fits(r, c, w, h) {
            for (let dr = 0; dr < h; dr++) {
                ensure(r + dr);
                for (let dc = 0; dc < w; dc++)
                    if (occ[r + dr][c + dc]) return false;
            }
            return true;
        }

        items.forEach(it => {
            if (it.header) {
                const r = occ.length;
                ensure(r);
                occ[r] = [true, true, true, true];
                rowH[r] = headerHeight;
                map[it.entry.id] = { col: 0, row: r, w: 4, h: 1, header: true };
                floor = r + 1;
                return;
            }
            let r = floor;
            for (;; r++) {
                let found = -1;
                for (let c = 0; c + it.w <= 4; c++) {
                    if (fits(r, c, it.w, it.h)) {
                        found = c;
                        break;
                    }
                }
                if (found >= 0) {
                    for (let dr = 0; dr < it.h; dr++)
                        for (let dc = 0; dc < it.w; dc++)
                            occ[r + dr][found + dc] = true;
                    map[it.entry.id] = { col: found, row: r, w: it.w, h: it.h };
                    break;
                }
            }
        });

        const rowY = [];
        let y = 0;
        rowH.forEach(h => {
            rowY.push(y);
            y += h + gap;
        });
        Object.keys(map).forEach(id => {
            const p = map[id];
            let height = 0;
            for (let dr = 0; dr < p.h; dr++) height += rowH[p.row + dr] + (dr > 0 ? gap : 0);
            p.y = rowY[p.row];
            p.height = height;
        });
        return { map: map, total: Math.max(0, y - gap), count: items.filter(i => !i.header).length };
    }

    readonly property var tokens: normalized(query).split(/\s+/).filter(t => t.length > 0)
    readonly property var layoutResult: computeLayout(tokens)
    readonly property var layoutMap: layoutResult.map

    onTokensChanged: flick.contentY = 0

    Component.onCompleted: {
        if (WM.compositor === "hyprland") HyprlandOptions.refresh();
    }

    function scrollBy(delta) {
        flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + delta));
    }


        Flickable {
            id: flick
            anchors.fill: parent
            clip: true
            contentWidth: width
            contentHeight: root.layoutResult.total
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 4000
            maximumFlickVelocity: 2500

            Behavior on contentY {
                enabled: !flick.moving && !flick.dragging
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            Item {
                id: canvas
                width: flick.width
                height: root.layoutResult.total

                Repeater {
                    model: root.allEntries

                    delegate: Loader {
                        id: slot
                        required property int index
                        required property var modelData

                        readonly property var place: root.layoutMap[modelData.id] ?? null
                        property var lastPlace: null
                        property bool ready: false
                        readonly property var shown: place ?? lastPlace
                        readonly property real colW: (canvas.width - root.gap * 3) / 4
                        readonly property bool inView: place !== null
                            && place.y + place.height > flick.contentY - 240
                            && place.y < flick.contentY + flick.height + 240

                        onPlaceChanged: {
                            if (place) lastPlace = place;
                        }
                        Component.onCompleted: Qt.callLater(() => { ready = true; })

                        x: shown ? shown.col * (colW + root.gap) : 0
                        y: shown ? shown.y : 0
                        width: shown ? shown.w * colW + (shown.w - 1) * root.gap : 0
                        height: shown ? shown.height : 0
                        opacity: place ? 1 : 0
                        scale: place ? 1 : 0.6
                        visible: opacity > 0.01

                        Behavior on x { enabled: slot.ready; SpringAnimation { spring: 3.2; damping: 0.28 } }
                        Behavior on y { enabled: slot.ready; SpringAnimation { spring: 3.2; damping: 0.28 } }
                        Behavior on width { enabled: slot.ready; SpringAnimation { spring: 3.2; damping: 0.28 } }
                        Behavior on height { enabled: slot.ready; SpringAnimation { spring: 3.2; damping: 0.28 } }
                        Behavior on opacity { enabled: slot.ready; NumberAnimation { duration: 180 } }
                        Behavior on scale { enabled: slot.ready; SpringAnimation { spring: 3.2; damping: 0.3 } }

                        active: place !== null && (modelData.kind === "header" || inView)
                        sourceComponent: modelData.kind === "header" ? headerComponent
                            : modelData.type === "style" ? styleComponent
                            : modelData.type === "schemes" ? schemesComponent
                            : modelData.type === "barpos" ? barposComponent
                            : modelData.type === "toggle" ? toggleComponent
                            : modelData.type === "slider" ? sliderComponent
                            : modelData.type === "spin" ? spinComponent
                            : modelData.type === "combo" ? comboComponent
                            : modelData.type === "text" ? textComponent
                            : modelData.type === "swatch" ? swatchComponent
                            : modelData.type === "shape" ? shapeComponent
                            : modelData.type === "barlayout" ? barLayoutComponent
                            : modelData.type === "palette" ? paletteComponent
                            : modelData.type === "duration" ? durationComponent
                            : modelData.type === "iconpicker" ? iconPickerComponent
                            : modelData.type === "weathermap" ? weatherMapComponent
                            : selectComponent

                        Component {
                            id: headerComponent

                            RowLayout {
                                anchors.fill: parent
                                spacing: 10

                                Rectangle {
                                    radius: height / 2
                                    color: Appearance.colors.colPrimaryContainer
                                    implicitHeight: 32
                                    implicitWidth: headerChip.implicitWidth + 22

                                    RowLayout {
                                        id: headerChip
                                        anchors.centerIn: parent
                                        spacing: 8

                                        MaterialSymbol {
                                            text: slot.modelData.icon
                                            iconSize: 18
                                            fill: 1
                                            color: Appearance.colors.colOnPrimaryContainer
                                        }
                                        StyledText {
                                            text: slot.modelData.title
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colOnPrimaryContainer
                                        }
                                    }
                                }

                                StyledText {
                                    text: slot.modelData.count
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 2
                                    radius: 1
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0; color: Appearance.colors.colPrimary }
                                        GradientStop { position: 0.35; color: Appearance.colors.colOutlineVariant }
                                        GradientStop { position: 1; color: "transparent" }
                                    }
                                }

                                StyledText {
                                    visible: slot.modelData.page !== ""
                                    text: slot.modelData.page.toUpperCase()
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.5
                                    color: Appearance.colors.colSubtext
                                    opacity: 0.7
                                }
                            }
                        }

                        Component {
                            id: styleComponent
                            DashboardStyleCard {
                                anchors.fill: parent
                                pager: root.pager
                                staggerMs: root.staggerMs
                                animIndex: slot.index % 6
                                travelX: slot.modelData.travelX
                                travelY: slot.modelData.travelY
                            }
                        }

                        Component {
                            id: schemesComponent
                            DashboardSchemeCard {
                                anchors.fill: parent
                                pager: root.pager
                                staggerMs: root.staggerMs
                                animIndex: slot.index % 6
                                travelX: slot.modelData.travelX
                                travelY: slot.modelData.travelY
                            }
                        }

                        Component {
                            id: barposComponent
                            DashboardBarPositionCard {
                                anchors.fill: parent
                                pager: root.pager
                                staggerMs: root.staggerMs
                                animIndex: slot.index % 6
                                travelX: slot.modelData.travelX
                                travelY: slot.modelData.travelY
                            }
                        }

                        Component {
                            id: toggleComponent
                            DashboardToggleCard {
                                anchors.fill: parent
                                controlKey: slot.modelData.key
                                override: catalog.controlFor(slot.modelData.key)
                                title: slot.modelData.title
                                icon: slot.modelData.icon
                                tileShape: slot.modelData.shape
                                pager: root.pager
                                staggerMs: root.staggerMs
                                animIndex: slot.index % 6
                                travelX: slot.modelData.travelX
                                travelY: slot.modelData.travelY
                            }
                        }

                        Component {
                            id: sliderComponent
                            DashboardSliderCard {
                                anchors.fill: parent
                                controlKey: slot.modelData.key
                                override: catalog.controlFor(slot.modelData.key)
                                title: slot.modelData.title
                                icon: slot.modelData.icon
                                tileShape: slot.modelData.shape
                                showPercent: slot.modelData.percent !== false
                                pager: root.pager
                                staggerMs: root.staggerMs
                                animIndex: slot.index % 6
                                travelX: slot.modelData.travelX
                                travelY: slot.modelData.travelY
                            }
                        }

                        Component {
                            id: spinComponent
                            DashboardSpinCard {
                                anchors.fill: parent
                                controlKey: slot.modelData.key
                                override: catalog.controlFor(slot.modelData.key)
                                title: slot.modelData.title
                                icon: slot.modelData.icon
                                tileShape: slot.modelData.shape
                                pager: root.pager
                                staggerMs: root.staggerMs
                                animIndex: slot.index % 6
                                travelX: slot.modelData.travelX
                                travelY: slot.modelData.travelY
                            }
                        }

                        Component {
                            id: comboComponent
                            DashboardComboCard {
                                anchors.fill: parent
                                controlKey: slot.modelData.key
                                override: catalog.controlFor(slot.modelData.key)
                                title: slot.modelData.title
                                icon: slot.modelData.icon
                                tileShape: slot.modelData.shape
                                pager: root.pager
                                staggerMs: root.staggerMs
                                animIndex: slot.index % 6
                                travelX: slot.modelData.travelX
                                travelY: slot.modelData.travelY
                            }
                        }

                        Component {
                            id: textComponent
                            DashboardTextCard {
                                anchors.fill: parent
                                placeholder: slot.modelData.placeholder ?? ""
                                controlKey: slot.modelData.key
                                override: catalog.controlFor(slot.modelData.key)
                                title: slot.modelData.title
                                icon: slot.modelData.icon
                                tileShape: slot.modelData.shape
                                pager: root.pager
                                staggerMs: root.staggerMs
                                animIndex: slot.index % 6
                                travelX: slot.modelData.travelX
                                travelY: slot.modelData.travelY
                            }
                        }

                        Component {
                            id: weatherMapComponent
                            DashboardWeatherMapCard {
                                anchors.fill: parent
                                pager: root.pager
                                staggerMs: root.staggerMs
                                animIndex: slot.index % 6
                                travelX: slot.modelData.travelX
                                travelY: slot.modelData.travelY
                            }
                        }

                        Component {
                            id: swatchComponent
                            DashboardSwatchCard {
                                anchors.fill: parent
                                controlKey: slot.modelData.key
                                override: catalog.controlFor(slot.modelData.key)
                                title: slot.modelData.title
                                icon: slot.modelData.icon
                                tileShape: slot.modelData.shape
                                pager: root.pager
                                staggerMs: root.staggerMs
                                animIndex: slot.index % 6
                                travelX: slot.modelData.travelX
                                travelY: slot.modelData.travelY
                            }
                        }

                        Component {
                            id: shapeComponent
                            DashboardShapeCard {
                                anchors.fill: parent
                                controlKey: slot.modelData.key
                                override: catalog.controlFor(slot.modelData.key)
                                title: slot.modelData.title
                                icon: slot.modelData.icon
                                tileShape: slot.modelData.shape
                                pager: root.pager
                                staggerMs: root.staggerMs
                                animIndex: slot.index % 6
                                travelX: slot.modelData.travelX
                                travelY: slot.modelData.travelY
                            }
                        }

                        Component {
                            id: barLayoutComponent
                            DashboardBarLayoutCard {
                                anchors.fill: parent
                                title: slot.modelData.title
                                icon: slot.modelData.icon
                                tileShape: slot.modelData.shape
                                pager: root.pager
                                staggerMs: root.staggerMs
                                animIndex: slot.index % 6
                                travelX: slot.modelData.travelX
                                travelY: slot.modelData.travelY
                            }
                        }

                        Component {
                            id: paletteComponent
                            DashboardPaletteCard {
                                anchors.fill: parent
                                controlKey: slot.modelData.key
                                override: catalog.controlFor(slot.modelData.key)
                                title: slot.modelData.title
                                icon: slot.modelData.icon
                                tileShape: slot.modelData.shape
                                pager: root.pager
                                staggerMs: root.staggerMs
                                animIndex: slot.index % 6
                                travelX: slot.modelData.travelX
                                travelY: slot.modelData.travelY
                            }
                        }

                        Component {
                            id: durationComponent
                            DashboardDurationCard {
                                anchors.fill: parent
                                controlKey: slot.modelData.key
                                override: catalog.controlFor(slot.modelData.key)
                                title: slot.modelData.title
                                icon: slot.modelData.icon
                                tileShape: slot.modelData.shape
                                pager: root.pager
                                staggerMs: root.staggerMs
                                animIndex: slot.index % 6
                                travelX: slot.modelData.travelX
                                travelY: slot.modelData.travelY
                            }
                        }

                        Component {
                            id: iconPickerComponent
                            DashboardIconCard {
                                anchors.fill: parent
                                title: slot.modelData.title
                                icon: slot.modelData.icon
                                tileShape: slot.modelData.shape
                                pager: root.pager
                                staggerMs: root.staggerMs
                                animIndex: slot.index % 6
                                travelX: slot.modelData.travelX
                                travelY: slot.modelData.travelY
                            }
                        }

                        Component {
                            id: selectComponent
                            DashboardSelectCard {
                                anchors.fill: parent
                                controlKey: slot.modelData.key
                                override: catalog.controlFor(slot.modelData.key)
                                title: slot.modelData.title
                                icon: slot.modelData.icon
                                tileShape: slot.modelData.shape
                                pager: root.pager
                                staggerMs: root.staggerMs
                                animIndex: slot.index % 6
                                travelX: slot.modelData.travelX
                                travelY: slot.modelData.travelY
                            }
                        }
                    }
                }
            }
        }
}
