local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local util = require("util")
local L = require("libraryxi18n").t
local Settings = require("libraryxsettings")
local Screen = Device.screen

local BookDetails = InputContainer:extend{
    plugin = nil, ui = nil, book = nil, cover_image = nil,
    on_read = nil, on_favorites = nil,
}

local function scaledFace(name, base_size, percent)
    local size = math.max(10, math.floor(base_size * percent / 100 + 0.5))
    return Font:getFace(name, size)
end

local function textWidget(text, width, face, alignment, bold)
    return TextBoxWidget:new{
        text = tostring(text or ""), width = width, face = face,
        alignment = alignment or "left", bold = bold,
    }
end

local function addText(group, text, width, face, alignment, bold, gap)
    if text and text ~= "" then
        if #group > 0 and gap then
            table.insert(group, VerticalSpan:new{ width = gap })
        end
        table.insert(group, textWidget(text, width, face, alignment, bold))
    end
end

function BookDetails:init()
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    local frame_w = math.floor(screen_w * 0.96)
    local frame_h = math.floor(screen_h * 0.96)
    local outer_padding = Screen:scaleBySize(10)
    local content_w = frame_w - 2 * outer_padding

    self.button_table = ButtonTable:new{
        width = content_w, zero_sep = true, show_parent = self,
        buttons = {{
            {
                text = L("read_book"),
                callback = function() if self.on_read then self.on_read() end end,
            },
            {
                text = L("favorites"),
                callback = function() if self.on_favorites then self.on_favorites() end end,
            },
            { text = "×", callback = function() self:onClose() end },
        }},
    }

    local scroll_h = frame_h - self.button_table:getSize().h
        - 2 * outer_padding - Screen:scaleBySize(6)
    local body = VerticalGroup:new{ align = "center" }

    if self.cover_image then
        local cover_scale = Settings.detailsCoverScale() / 100
        local max_cover_w = math.floor(content_w * 0.84 * cover_scale)
        local max_cover_h = math.floor(scroll_h * 0.70 * cover_scale)
        local cover = ImageWidget:new{
            image = self.cover_image, image_disposable = true,
            scale_factor = 0, width = max_cover_w, height = max_cover_h,
            alpha = false,
        }
        table.insert(body, CenterContainer:new{
            dimen = Geom:new{ w = content_w, h = max_cover_h }, cover,
        })
        table.insert(body, VerticalSpan:new{ width = Screen:scaleBySize(18) })
    else
        table.insert(body, textWidget(L("no_cover"), content_w,
            scaledFace("smallinfofont", 22, Settings.detailsBodyScale()), "center"))
        table.insert(body, VerticalSpan:new{ width = Screen:scaleBySize(14) })
    end

    addText(body, self.book.title, content_w,
        scaledFace("tfont", 26, Settings.detailsTitleScale()),
        "center", false, Screen:scaleBySize(8))
    local authors = self.book.authors and self.book.authors:gsub("\n", ", ") or ""
    addText(body, authors, content_w,
        scaledFace("infofont", 24, Settings.detailsBodyScale()),
        "center", false, Screen:scaleBySize(12))

    local description = self.book.description
    if description and description ~= "" then
        addText(body, util.htmlToPlainTextIfHtml(description), content_w,
            scaledFace("infofont", 24, Settings.detailsBodyScale()),
            "left", false, Screen:scaleBySize(24))
    end

    local meta = {}
    if Settings.detailsShowMetadata()
            and self.book.series and self.book.series ~= "" then
        local series = self.book.series
        if self.book.series_index then
            series = series .. " • " .. tostring(self.book.series_index)
        end
        meta[#meta + 1] = '"' .. series .. '"'
    end
    if Settings.detailsShowGenres()
            and self.book.genres and self.book.genres ~= "" then
        meta[#meta + 1] = self.book.genres:gsub("\n", ", ")
    end
    if Settings.detailsShowMetadata() then
        local lang = self.book.language and self.book.language:upper() or ""
        if lang ~= "" then meta[#meta + 1] = '"' .. lang .. '"' end
        if self.book.filesize and self.book.filesize > 0 then
            meta[#meta + 1] = util.getFriendlySize(self.book.filesize)
        end
    end
    if #meta > 0 then
        addText(body, table.concat(meta, "\n"), content_w,
            scaledFace("smallinfofont", 22, Settings.detailsBodyScale()),
            "left", false, Screen:scaleBySize(24))
    end
    if Settings.detailsShowPath()
            and self.book.path and self.book.path ~= "" then
        addText(body, self.book.path, content_w,
            scaledFace("x_smallinfofont", 20, Settings.detailsBodyScale()),
            "left", false, Screen:scaleBySize(24))
    end

    self.scroll_widget = ScrollableContainer:new{
        dimen = Geom:new{ w = content_w, h = scroll_h },
        show_parent = self, body,
    }
    self.cropping_widget = self.scroll_widget

    self.frame = FrameContainer:new{
        width = frame_w, height = frame_h,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window, radius = Size.radius.window,
        padding = outer_padding,
        VerticalGroup:new{
            self.scroll_widget,
            VerticalSpan:new{ width = Screen:scaleBySize(6) },
            CenterContainer:new{
                dimen = Geom:new{
                    w = content_w, h = self.button_table:getSize().h,
                },
                self.button_table,
            },
        },
    }

    self[1] = CenterContainer:new{ dimen = Screen:getSize(), self.frame }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
end

function BookDetails:onClose()
    UIManager:close(self)
    return true
end

function BookDetails:onMultiSwipe()
    self:onClose()
    return true
end

function BookDetails:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self.frame and self.frame.dimen or nil
    end)
end

return BookDetails
