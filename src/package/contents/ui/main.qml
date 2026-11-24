import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    // 在面板中直接显示图标，左键点击即可切换，无需先展开弹窗。
    preferredRepresentation: fullRepresentation

    property bool isDark: false

    property string helperFile: decodeURIComponent(
        Qt.resolvedUrl("../code/darklight-toggle").toString().replace(/^file:\/\//, "")
    )

    function shellQuote(text) {
        return "'" + String(text).replace(/'/g, "'\\''") + "'";
    }

    function statusCommand() {
        return "python3 " + shellQuote(helperFile) + " status";
    }

    function toggleCommand() {
        return "python3 " + shellQuote(helperFile) + " toggle";
    }

    function applyResult(output) {
        var value = String(output || "").trim();
        if (value === "dark" || value === "light") {
            root.isDark = (value === "dark");
        }
    }

    function toggle() {
        actionSource.run(toggleCommand());
    }

    // 低频轮询，保证通过系统设置或定时任务改变主题后图标仍然同步。
    Plasma5Support.DataSource {
        id: statusSource
        engine: "executable"
        interval: 30000
        connectedSources: [statusCommand()]
        onNewData: (sourceName, data) => {
            if (data && data["stdout"]) applyResult(data["stdout"]);
        }
    }

    // 一次性命令源，每次点击复用，避免频繁创建/销毁数据源。
    Plasma5Support.DataSource {
        id: actionSource
        engine: "executable"
        connectedSources: []

        function run(command) {
            actionSource.connectSource(command);
        }

        onNewData: (sourceName, data) => {
            if (data && data["stdout"]) applyResult(data["stdout"]);
            actionSource.disconnectSource(sourceName);
        }
    }

    toolTipMainText: i18n("深浅模式切换")
    toolTipSubText: root.isDark
        ? i18n("当前：深色模式（点击切换为浅色）")
        : i18n("当前：浅色模式（点击切换为深色）")

    Layout.preferredWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.smallSpacing * 2
    Layout.preferredHeight: Kirigami.Units.iconSizes.medium + Kirigami.Units.smallSpacing * 2
    Layout.minimumWidth: Kirigami.Units.iconSizes.small
    Layout.minimumHeight: Kirigami.Units.iconSizes.small

    Item {
        id: button
        anchors.fill: parent

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            // 图标随项目一起分发（拷贝自 Breeze 的 symbolic 单色图标），不依赖系统图标主题。
            // isMask + Theme.textColor 让描边取面板文字色，浅/深面板自动反色，风格与 KDE 面板一致。
            source: root.isDark ? Qt.resolvedUrl("icons/moon.svg") : Qt.resolvedUrl("icons/sun.svg")
            isMask: true
            color: Kirigami.Theme.textColor
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.toggle()
        }
    }
}
