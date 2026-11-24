// 未命中「系统设置 → 外观 → 全局主题」里预设的那对深浅主题时，弹出的系统通知。
//
// 单独成文件的原因：它依赖 org.kde.notification 插件。若该插件缺失，只有本文件
// 加载失败，小部件本体仍然可用（主界面用 Loader 装载，错误会被忽略）。
import QtQuick
import org.kde.notification

Item {
    id: root

    // 本次实际使用的主题名（由切换脚本输出），用于让用户知道推断成了什么。
    property string themeName: ""

    signal configureRequested()

    function show(themeName) {
        root.themeName = String(themeName || "");
        notice.sendEvent();
    }

    Notification {
        id: notice
        componentName: "darklightswitch"
        eventId: "preset-missing"
        iconName: "preferences-desktop-theme"
        urgency: Notification.NormalUrgency
        // 提示需要在用户操作时仍能点到按钮，所以不自动消失。
        flags: Notification.Persistent
        title: i18n("未配置深浅主题预设")
        text: root.themeName.length > 0
            ? i18n("本次按名称推断或兜底选择了「%1」。到「系统设置 → 外观 → 全局主题」里指定浅色与深色主题后，切换才会完全符合预期。", root.themeName)
            : i18n("本次按名称推断或兜底选择了主题。到「系统设置 → 外观 → 全局主题」里指定浅色与深色主题后，切换才会完全符合预期。")

        actions: [
            NotificationAction {
                label: i18n("打开外观设置")
                onActivated: root.configureRequested()
            }
        ]
    }
}
