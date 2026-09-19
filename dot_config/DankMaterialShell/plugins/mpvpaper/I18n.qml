pragma Singleton

import QtQuick
import "./translations.js" as Translations

QtObject {
    property string language: "en"

    function tr(term, context) {
        return Translations.tr(language, term)
    }
}
