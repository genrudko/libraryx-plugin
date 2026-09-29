local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local LibraryX = WidgetContainer:extend{
    name = "libraryx",
    is_doc_only = false,
}

function LibraryX:init()
    if not self.ui.document and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function LibraryX:addToMainMenu(menu_items)
    menu_items.libraryx = {
        text = _("LibraryX"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Compatibility probe"),
                callback = function()
                    local Compat = require("compat")
                    Compat.run(self)
                end,
            },
            {
                text = _("About LibraryX"),
                callback = function()
                    local TextViewer = require("ui/widget/textviewer")
                    UIManager:show(TextViewer:new{
                        title = _("LibraryX"),
                        text = _([[
M0 compatibility spike

Goal: prove that the target KOReader build exposes the SQLite,
metadata, reading-state and history APIs required by LibraryX.

No library scanning or replacement home screen is enabled yet.
]]),
                    })
                end,
            },
        },
    }
end

return LibraryX
