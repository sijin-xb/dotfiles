import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "cavaVisualizer"

    // ---------------------------------------------------------------
    // Visualisation mode  (drives conditional visibility below)
    // ---------------------------------------------------------------

    SelectionSetting {
        id: vizModeSetting
        settingKey:   "vizMode"
        label:        I18n.tr("Visualisation Mode")
        defaultValue: "bars"
        options: [
            { label: I18n.tr("Bars"),          value: "bars"          },
            { label: I18n.tr("Curve Outline"), value: "curve-outline" },
            { label: I18n.tr("Curve Filled"),  value: "curve-filled"  }
        ]
    }

    // ---------------------------------------------------------------
    // Layout  (bars only)
    // ---------------------------------------------------------------

    SliderSetting {
        visible:      vizModeSetting.value === "bars"
        settingKey:   "barCount"
        description:  I18n.tr("Stereo needs an even number.")
        label:        I18n.tr("Bar Count")
        defaultValue: 20
        minimum:      4
        maximum:      128
    }

    SliderSetting {
        visible:      vizModeSetting.value === "bars"
        settingKey:   "barSpacing"
        label:        I18n.tr("Bar Spacing")
        defaultValue: 4
        minimum:      0
        maximum:      32
        unit:         "px"
    }

    SliderSetting {
        visible:      vizModeSetting.value === "bars"
        settingKey:   "barWidth"
        label:        I18n.tr("Bar Width")
        description:  I18n.tr("Fixed bar width in pixels. Set to 0 to fill the widget evenly.")
        defaultValue: 0
        minimum:      0
        maximum:      32
        unit:         "px"
    }

    // ---------------------------------------------------------------
    // Layout  (curve only)
    // ---------------------------------------------------------------

    SliderSetting {
        visible:      vizModeSetting.value !== "bars"
        settingKey:   "curvePoints"
        label:        I18n.tr("Sample Points")
        description:  I18n.tr("Number of frequency bands sampled for the curve. Stereo needs an even number.")
        defaultValue: 32
        minimum:      8
        maximum:      128
    }

    SliderSetting {
        visible:      vizModeSetting.value !== "bars"
        settingKey:   "curveLineWidth"
        label:        I18n.tr("Line Width")
        defaultValue: 2
        minimum:      1
        maximum:      8
        unit:         "px"
    }

    // ---------------------------------------------------------------
    // Orientation
    // ---------------------------------------------------------------

    SelectionSetting {
        settingKey:   "orientation"
        label:        I18n.tr("Orientation")
        defaultValue: "bottom"
        options: [
            { label: I18n.tr("Bottom"),     value: "bottom"     },
            { label: I18n.tr("Top"),        value: "top"        },
            { label: I18n.tr("Left"),       value: "left"       },
            { label: I18n.tr("Right"),      value: "right"      },
            { label: I18n.tr("Horizontal"), value: "horizontal" },
            { label: I18n.tr("Vertical"),   value: "vertical"   }
        ]
    }

    // ---------------------------------------------------------------
    // Audio
    // ---------------------------------------------------------------

    SliderSetting {
        settingKey:   "sensitivity"
        label:        I18n.tr("Sensitivity")
        defaultValue: 100
        minimum:      10
        maximum:      300
        unit:         "%"
    }

    SelectionSetting {
        settingKey:   "channels"
        label:        I18n.tr("Channels")
        description:  I18n.tr("Stereo mirrors both channels with low frequencies in the center. Mono outputs left to right, lowest to highest frequency.")
        defaultValue: "mono"
        options: [
            { label: I18n.tr("Mono"),   value: "mono"   },
            { label: I18n.tr("Stereo"), value: "stereo" }
        ]
    }

    // ---------------------------------------------------------------
    // Appearance
    // ---------------------------------------------------------------

    SelectionSetting {
        settingKey:   "colorChoice"
        label:        I18n.tr("Colour")
        defaultValue: "primary"
        options: [
            { label: I18n.tr("Primary"),   value: "primary"   },
            { label: I18n.tr("Secondary"), value: "secondary" },
            { label: I18n.tr("Surface"),   value: "surface"   }
        ]
    }

    SliderSetting {
        settingKey:   "silenceTimeout"
        label:        I18n.tr("Fade Out Delay")
        description:  I18n.tr("Seconds of silence before the widget fades out")
        defaultValue: 5
        minimum:      1
        maximum:      30
        unit:         "s"
    }

    SliderSetting {
        settingKey:   "bgOpacity"
        label:        I18n.tr("Background Opacity")
        defaultValue: 0
        minimum:      0
        maximum:      100
        unit:         "%"
    }

    SliderSetting {
        settingKey:   "opacity"
        label:        I18n.tr("Opacity")
        defaultValue: 100
        minimum:      0
        maximum:      100
        unit:         "%"
    }
}
