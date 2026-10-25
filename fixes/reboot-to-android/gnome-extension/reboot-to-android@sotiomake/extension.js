import {Extension} from "resource:///org/gnome/shell/extensions/extension.js";
import * as Main from "resource:///org/gnome/shell/ui/main.js";
import * as PopupMenu from "resource:///org/gnome/shell/ui/popupMenu.js";
import * as ModalDialog from "resource:///org/gnome/shell/ui/modalDialog.js";
import * as Dialog from "resource:///org/gnome/shell/ui/dialog.js";
import GLib from "gi://GLib";
import Clutter from "gi://Clutter";

class AndroidRebootDialog extends ModalDialog.ModalDialog {
    constructor() {
        super({ styleClass: "end-session-dialog" });

        const content = new Dialog.MessageDialogContent({
            title: "Перезапуск в Android",
            description: "Планшет будет перезагружен в систему Android (ZUI).\n\nВсе несохранённые данные в Linux будут потеряны.",
        });

        this.contentLayout.add_child(content);

        this.addButton({
            label: "Отмена",
            action: () => this.close(),
            key: Clutter.KEY_Escape,
        });

        this.addButton({
            label: "Перезагрузить",
            action: () => {
                this.close();
                GLib.spawn_command_line_async("sudo /usr/local/sbin/back-to-android");
            },
            default: true,
        });
    }
}

export default class RebootToAndroidExtension extends Extension {
    enable() {
        this._menuItem = null;
        this._separator = null;
        this._menu = null;

        this._idleId = GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            this._idleId = 0;
            this._setupMenu();
            return GLib.SOURCE_REMOVE;
        });
    }

    _setupMenu() {
        const qs = Main.panel.statusArea.quickSettings;
        if (!qs) return;

        // Find system item / power menu
        if (qs._system && qs._system.quickSettingsElement) {
            const el = qs._system.quickSettingsElement;
            if (el._systemItem && el._systemItem.menu) {
                this._menu = el._systemItem.menu;
            }
        }

        if (!this._menu && qs.menu) {
            for (const child of qs.menu._grid.get_children()) {
                if (child.menu && child.menu.setHeader) {
                    this._menu = child.menu;
                    break;
                }
            }
        }

        if (!this._menu && qs._overlay) {
            for (const child of qs._overlay.get_children()) {
                if (child._delegate && child._delegate.setHeader) {
                    this._menu = child._delegate;
                    break;
                }
            }
        }

        if (!this._menu) {
            console.error("reboot-to-android: Could not locate shutdown menu");
            return;
        }

        console.log("reboot-to-android: Found shutdown menu, adding Android reboot item");

        this._separator = new PopupMenu.PopupSeparatorMenuItem();
        this._menu.addMenuItem(this._separator);

        this._menuItem = new PopupMenu.PopupImageMenuItem("Перезапуск в Android…", "smartphone-symbolic");
        this._menuItem.connect("activate", () => {
            Main.panel.closeQuickSettings();
            const dialog = new AndroidRebootDialog();
            dialog.open();
        });

        this._menu.addMenuItem(this._menuItem);
    }

    disable() {
        if (this._idleId) {
            GLib.source_remove(this._idleId);
            this._idleId = 0;
        }
        if (this._menuItem) {
            this._menuItem.destroy();
            this._menuItem = null;
        }
        if (this._separator) {
            this._separator.destroy();
            this._separator = null;
        }
        this._menu = null;
    }
}
