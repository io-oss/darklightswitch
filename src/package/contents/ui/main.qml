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
        // 切换要等 GTK 通道对齐后再补发一次通知，耗时约 1～1.5 秒；
        // 先按用户预期翻转图标，命令返回后再用真实状态校正。
        root.isDark = !root.isDark;
        actionSource.run(toggleCommand());
    }

    // 切换脚本的提示前缀：命中不了预设时它会把「本次实际用了哪个主题」写到 stderr。
    // 这个前缀在脚本里是 NOTICE_PREFIX，两处必须保持一致。
    readonly property string noticeMarker: "darklight-toggle: 提示：未配置深浅主题预设"

    // 每个会话只提示一次，避免每次点击都弹。
    property bool presetNoticeShown: false
    property string pendingNoticeTheme: ""

    function maybeAnnounce(stderrText) {
        if (root.presetNoticeShown) return;
        var text = String(stderrText || "");
        var start = text.indexOf(root.noticeMarker);
        if (start < 0) return;
        root.presetNoticeShown = true;
        var end = text.indexOf("\n", start);
        var line = end < 0 ? text.substring(start) : text.substring(start, end);
        // 前缀之后、最后一个「：」之后是主题名。
        var theme = line.substring(line.lastIndexOf("：") + 1).trim();
        if (noticeLoader.item) noticeLoader.item.show(theme);
        else root.pendingNoticeTheme = theme;
    }

    function openAppearanceSettings() {
        var command = "systemsettings kcm_lookandfeel >/dev/null 2>&1 || kcmshell6 kcm_lookandfeel";
        openerSource.run("sh -c " + shellQuote(command));
    }

    // 低频轮询，保证通过系统设置或定时任务改变主题后图标仍然同步。
    Plasma5Support.DataSource {
        id: statusSource
        engine: "executable"
        interval: 30000
        connectedSources: [statusCommand()]
        onNewData: (sourceName, data) => {
            if (data && data["stdout"]) applyResult(data["stdout"]);
            if (data && data["stderr"]) maybeAnnounce(data["stderr"]);
        }
    }

    // 通知组件单独成文件：缺少 KNotifications QML 插件时只有它加载失败，小部件本体不受影响。
    Loader {
        id: noticeLoader
        source: "PresetNotice.qml"
        onStatusChanged: {
            if (status === Loader.Error) console.warn("darklightswitch: 通知组件加载失败");
        }
        onLoaded: {
            item.configureRequested.connect(root.openAppearanceSettings);
            if (root.pendingNoticeTheme !== "") {
                item.show(root.pendingNoticeTheme);
                root.pendingNoticeTheme = "";
            }
        }
    }

    // 只用一次：点击通知里的按钮时打开「外观 → 全局主题」。
    Plasma5Support.DataSource {
        id: openerSource
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => openerSource.disconnectSource(sourceName)
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
            actionSource.disconnectSource(sourceName);
            var code = data && data["exit code"] !== undefined ? parseInt(data["exit code"], 10) : 0;
            if (!isNaN(code) && code !== 0) {
                // 切换失败：重读一次真实状态，纠正刚才乐观翻转的图标。
                actionSource.run(statusCommand());
                return;
            }
            if (data && data["stdout"]) applyResult(data["stdout"]);
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
