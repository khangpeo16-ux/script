--========================================================
-- WEB COSPLAY ALBUM BROWSER V4
--
-- FLOW:
-- ALL ALBUMS
--      ↓
-- OPEN ALBUM / VIEW IMAGE
--      ↓
-- CLICK CREATOR NAME
--      ↓
-- ALL ALBUMS FROM CREATOR
--
-- FEATURES:
-- • Full screen
-- • Background scanner
-- • Progressive results
-- • Search button
-- • Search album / creator
-- • Click creator -> creator albums
-- • Image viewer
-- • Cache
-- • Retry x3
-- • Preload previous / next
-- • Floating GUI toggle
-- • Mobile friendly
--========================================================

local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

--========================================================
-- CONFIG
--========================================================

local SCAN_PAGES = {
    "https://cosplaytele.com/category/cosplay-nudee/",

    -- THÊM LINK:
    -- "https://cosplaytele.com/....",
}

local MAX_PAGES = 20

-- 0 = unlimited
local MAX_ALBUMS = 500

local SCAN_WORKERS = 3
local REQUEST_DELAY = 0.10

local IMAGE_RETRIES = 3
local PRELOAD_IMAGES = true

local CACHE_FOLDER =
    "cosplay_album_v4"

--========================================================
-- EXECUTOR
--========================================================

local getAsset =
    getcustomasset
    or getsynasset

local httpRequest =
    request
    or http_request
    or (syn and syn.request)

if not getAsset then
    warn("[ALBUM] getcustomasset/getsynasset not supported")
    return
end

if not writefile or not isfile then
    warn("[ALBUM] writefile/isfile not supported")
    return
end

--========================================================
-- UI PARENT
--========================================================

local UI_PARENT = CoreGui

pcall(function()
    if gethui then
        UI_PARENT = gethui()
    end
end)

--========================================================
-- REMOVE OLD
--========================================================

pcall(function()
    local old = UI_PARENT:FindFirstChild("COSPLAY_ALBUM_V4")
    if old then old:Destroy() end
end)

pcall(function()
    local old = UI_PARENT:FindFirstChild("COSPLAY_ALBUM_TOGGLE_V4")
    if old then old:Destroy() end
end)

--========================================================
-- SCREEN GUIS
--========================================================

local gui = Instance.new("ScreenGui")
gui.Name = "COSPLAY_ALBUM_V4"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = UI_PARENT

local toggleGui = Instance.new("ScreenGui")
toggleGui.Name = "COSPLAY_ALBUM_TOGGLE_V4"
toggleGui.ResetOnSpawn = false
toggleGui.IgnoreGuiInset = true
toggleGui.DisplayOrder = 1000
toggleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
toggleGui.Parent = UI_PARENT

--========================================================
-- HELPERS
--========================================================

local function corner(obj, radius)

    local c = Instance.new("UICorner")

    c.CornerRadius =
        UDim.new(0, radius or 12)

    c.Parent = obj

    return c
end

local function trim(s)

    s = tostring(s or "")

    return s
        :gsub("^%s+", "")
        :gsub("%s+$", "")
end

local function decodeHTML(s)

    if not s then
        return ""
    end

    s = s:gsub("&amp;", "&")
    s = s:gsub("&quot;", '"')
    s = s:gsub("&#039;", "'")
    s = s:gsub("&#8211;", "–")
    s = s:gsub("&#8212;", "—")
    s = s:gsub("&nbsp;", " ")
    s = s:gsub("&lt;", "<")
    s = s:gsub("&gt;", ">")

    return trim(s)
end

local function stripTags(s)

    s = tostring(s or "")

    s = s:gsub("<script.->.-</script>", "")
    s = s:gsub("<style.->.-</style>", "")
    s = s:gsub("<[^>]->", " ")
    s = s:gsub("%s+", " ")

    return decodeHTML(s)
end

local function normalizeSearch(s)

    s = tostring(s or ""):lower()

    s = s:gsub("_", " ")
    s = s:gsub("%-", " ")
    s = s:gsub("%s+", " ")

    return trim(s)
end

local function makeButton(parent, text, size, position)

    local b = Instance.new("TextButton")

    b.Size = size
    b.Position = position

    b.BackgroundColor3 =
        Color3.fromRGB(17,17,17)

    b.BackgroundTransparency = .08
    b.BorderSizePixel = 0

    b.Text = text

    b.TextColor3 =
        Color3.new(1,1,1)

    b.TextSize = 14

    b.Font =
        Enum.Font.GothamBold

    b.AutoButtonColor = true

    b.Parent = parent

    corner(b, 11)

    return b
end

--========================================================
-- HTTP
--========================================================

local function requestURL(url)

    if not url then
        return nil
    end

    if httpRequest then

        local ok, response =
            pcall(function()

                return httpRequest({
                    Url = url,
                    Method = "GET",

                    Headers = {
                        ["User-Agent"] =
                            "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/130 Mobile Safari/537.36",

                        ["Accept"] =
                            "*/*",

                        ["Referer"] =
                            "https://cosplaytele.com/"
                    }
                })

            end)

        if ok and response then

            local body =
                response.Body
                or response.body

            local code =
                tonumber(
                    response.StatusCode
                    or response.Status
                    or response.status
                )

            if type(body) == "string"
            and #body > 50
            and (
                not code
                or (
                    code >= 200
                    and code < 300
                )
            ) then

                return body
            end
        end
    end

    local ok, body =
        pcall(function()
            return game:HttpGet(url)
        end)

    if ok
    and type(body) == "string"
    and #body > 50 then

        return body
    end

    return nil
end

--========================================================
-- URL
--========================================================

local function normalizeURL(url)

    if type(url) ~= "string" then
        return nil
    end

    url = decodeHTML(url)

    url = url:gsub("\\/", "/")
    url = url:gsub("\\u0026", "&")

    if url:sub(1,2) == "//" then

        url = "https:" .. url

    elseif url:sub(1,1) == "/" then

        url =
            "https://cosplaytele.com"
            .. url
    end

    return url
end

local function isImageURL(url)

    if type(url) ~= "string" then
        return false
    end

    local s = url:lower()

    return
        s:find("%.webp")
        or s:find("%.jpg")
        or s:find("%.jpeg")
        or s:find("%.png")
end

local function isUsefulImage(url)

    if not isImageURL(url) then
        return false
    end

    local s = url:lower()

    if not s:find(
        "/wp-content/uploads/",
        1,
        true
    ) then
        return false
    end

    local blocked = {
        "logo",
        "favicon",
        "avatar",
        "emoji",
        "icon",
        "placeholder",
        "loading",
        "banner",
        "gravatar"
    }

    for _, word in ipairs(blocked) do

        if s:find(word,1,true) then
            return false
        end
    end

    return true
end

--========================================================
-- CACHE
--========================================================

if makefolder and isfolder then

    if not isfolder(CACHE_FOLDER) then

        pcall(function()
            makefolder(CACHE_FOLDER)
        end)
    end
end

local function hashString(s)

    local hash = 5381

    for i = 1,#s do

        hash =
            (
                hash * 33
                + s:byte(i)
            )
            % 2147483647
    end

    return tostring(hash)
end

local function extension(url)

    local clean =
        url:match("^[^?]+")
        or url

    local ext =
        clean:lower():match(
            "%.([%a%d]+)$"
        )

    if ext == "jpeg" then
        ext = "jpg"
    end

    if ext ~= "jpg"
    and ext ~= "png"
    and ext ~= "webp" then

        ext = "webp"
    end

    return ext
end

local function cacheFile(url)

    local name =
        hashString(url)
        .. "."
        .. extension(url)

    if makefolder and isfolder then

        return
            CACHE_FOLDER
            .. "/"
            .. name
    end

    return "album_" .. name
end

local assetCache = {}
local downloading = {}

local function looksLikeHTML(data)

    if type(data) ~= "string" then
        return true
    end

    local start =
        data:sub(1,250):lower()

    return
        start:find("<!doctype",1,true)
        or start:find("<html",1,true)
end

--========================================================
-- IMAGE DOWNLOAD
--========================================================

local function downloadImage(url)

    if not url then
        return nil
    end

    if assetCache[url] then
        return assetCache[url]
    end

    while downloading[url] do

        task.wait(.03)

        if assetCache[url] then
            return assetCache[url]
        end
    end

    downloading[url] = true

    local file =
        cacheFile(url)

    if isfile(file) then

        local ok, asset =
            pcall(function()
                return getAsset(file)
            end)

        if ok and asset then

            assetCache[url] = asset
            downloading[url] = nil

            return asset
        end
    end

    for attempt = 1,IMAGE_RETRIES do

        local data =
            requestURL(url)

        if type(data) == "string"
        and #data > 500
        and not looksLikeHTML(data) then

            local saved =
                pcall(function()
                    writefile(file,data)
                end)

            if saved then

                local ok, asset =
                    pcall(function()
                        return getAsset(file)
                    end)

                if ok and asset then

                    assetCache[url] =
                        asset

                    downloading[url] =
                        nil

                    return asset
                end
            end
        end

        task.wait(.15 * attempt)
    end

    downloading[url] = nil

    return nil
end

--========================================================
-- POST PARSER
--========================================================

local function parsePostLinks(html)

    local result = {}
    local seen = {}

    if type(html) ~= "string" then
        return result
    end

    local function add(href,name)

        href =
            normalizeURL(href)

        if not href then
            return
        end

        if not href:find(
            "cosplaytele.com",
            1,
            true
        ) then
            return
        end

        href = href:gsub("#.*$","")
        href = href:gsub("%?.*$","")

        local lower =
            href:lower()

        local blocked =
            lower:find("/category/",1,true)
            or lower:find("/tag/",1,true)
            or lower:find("/author/",1,true)
            or lower:find("/page/",1,true)
            or lower:find("/feed/",1,true)
            or lower:find("/wp-content/",1,true)
            or lower:find("/wp-admin/",1,true)
            or lower:find("/wp-json/",1,true)
            or isImageURL(href)

        if blocked or seen[href] then
            return
        end

        name =
            stripTags(name)

        if #name < 3 then

            name =
                href:match(
                    "cosplaytele%.com/([^/?#]+)/?"
                )
                or "Album"

            name =
                name:gsub("%-"," ")
        end

        seen[href] = true

        table.insert(
            result,
            {
                URL = href,
                Name = name
            }
        )
    end

    for href,inside in html:gmatch(
        '<a[^>]-href%s*=%s*["\']([^"\']+)["\'][^>]*>(.-)</a>'
    ) do

        add(href,inside)
    end

    return result
end

--========================================================
-- IMAGE PARSER
--========================================================

local function parseImages(html)

    local images = {}
    local seen = {}

    if type(html) ~= "string" then
        return images
    end

    local function add(url)

        url =
            normalizeURL(url)

        if not url then
            return
        end

        url = url:gsub("%?.*$","")

        if not isUsefulImage(url) then
            return
        end

        -- Skip WP thumbnail if full version exists elsewhere.

        if url:lower():match(
            "%-%d+x%d+%.[%a%d]+$"
        ) then
            return
        end

        if seen[url] then
            return
        end

        seen[url] = true

        table.insert(images,url)
    end

    for url in html:gmatch(
        'href%s*=%s*["\']([^"\']+)["\']'
    ) do

        if isImageURL(url) then
            add(url)
        end
    end

    for url in html:gmatch(
        'src%s*=%s*["\']([^"\']+)["\']'
    ) do

        if isImageURL(url) then
            add(url)
        end
    end

    for url in html:gmatch(
        'data%-src%s*=%s*["\']([^"\']+)["\']'
    ) do

        if isImageURL(url) then
            add(url)
        end
    end

    for url in html:gmatch(
        'data%-lazy%-src%s*=%s*["\']([^"\']+)["\']'
    ) do

        if isImageURL(url) then
            add(url)
        end
    end

    for srcset in html:gmatch(
        'srcset%s*=%s*["\']([^"\']+)["\']'
    ) do

        for url in srcset:gmatch(
            "(https?://[^,%s]+)"
        ) do
            add(url)
        end
    end

    return images
end

--========================================================
-- CREATOR NAME
--========================================================

local function extractCosplayerFromHTML(html)

    if type(html) ~= "string" then
        return nil
    end

    -- Keep block/line boundaries so:
    -- <strong>Cosplayer:</strong> NAME<br>
    -- becomes one clean line: Cosplayer: NAME
    local text = html

    text = text:gsub("<[Bb][Rr]%s*/?>", "\n")
    text = text:gsub("</[Pp]%s*>", "\n")
    text = text:gsub("</[Dd][Ii][Vv]%s*>", "\n")
    text = text:gsub("</[Ll][Ii]%s*>", "\n")
    text = text:gsub("</[Tt][Dd]%s*>", "\n")
    text = text:gsub("</[Tt][Rr]%s*>", "\n")

    text = text:gsub("<script.->.-</script>", "")
    text = text:gsub("<style.->.-</style>", "")
    text = text:gsub("<[^>]->", "")
    text = decodeHTML(text)

    -- First choice: an actual line beginning with "Cosplayer:".
    for line in (text .. "\n"):gmatch("(.-)\n") do

        line = trim(line:gsub("\r", ""))

        local creator =
            line:match("^[Cc][Oo][Ss][Pp][Ll][Aa][Yy][Ee][Rr]%s*:%s*(.+)$")

        if creator then

            creator = trim(creator)

            -- Prevent another metadata field from being swallowed
            -- if the site places several fields on the same line.
            local cut = creator:find("%s+[A-Z][A-Za-z ]-%s*:")
            if cut then
                creator = trim(creator:sub(1, cut - 1))
            end

            if #creator >= 2 then
                return creator
            end
        end
    end

    -- Fallback for pages where markup removed all useful line breaks.
    local compact = text:gsub("%s+", " ")
    local creator = compact:match(
        "[Cc][Oo][Ss][Pp][Ll][Aa][Yy][Ee][Rr]%s*:%s*([^<\n\r]+)"
    )

    if creator then
        creator = trim(creator)

        local cut = creator:find("%s+[A-Z][A-Za-z ]-%s*:")
        if cut then
            creator = trim(creator:sub(1, cut - 1))
        end

        if #creator >= 2 then
            return creator
        end
    end

    return nil
end

local function creatorFromAlbum(html,name,url)

    -- Use the FULL album title as requested.
    -- Do not try to split creator names from URL/content anymore.
    local fullName = stripTags(name)

    if fullName and fullName ~= "" then
        return fullName
    end

    -- Rare fallback if the anchor/title is empty: use the full last URL slug.
    local cleanURL =
        tostring(url or "")
        :gsub("#.*$", "")
        :gsub("%?.*$", "")
        :gsub("/+$", "")

    local slug =
        cleanURL:match("/([^/]+)$")

    if slug and slug ~= "" then
        return trim(slug:gsub("%-", " "))
    end

    return "Album"
end

--========================================================
-- DATABASE
--========================================================

local ALBUMS = {}

local albumURLSeen = {}

local currentAlbumIndex = nil
local currentImageIndex = 1

local currentMode = "all"
local currentCreator = nil

local returnMode = "all"
local returnCreator = nil

local imageToken = 0

--========================================================
-- ROOT
--========================================================

local root = Instance.new("Frame")

root.Size =
    UDim2.fromScale(1,1)

root.BackgroundColor3 =
    Color3.fromRGB(7,7,7)

root.BorderSizePixel = 0

root.Parent = gui

--========================================================
-- HEADER
--========================================================

local header = Instance.new("Frame")

header.Size =
    UDim2.new(1,0,0,62)

header.BackgroundColor3 =
    Color3.fromRGB(10,10,10)

header.BackgroundTransparency = .04
header.BorderSizePixel = 0

header.Parent = root

local backButton =
    makeButton(
        header,
        "‹",
        UDim2.fromOffset(44,44),
        UDim2.fromOffset(9,9)
    )

backButton.TextSize = 27
backButton.Visible = false

local pageTitle =
    Instance.new("TextLabel")

pageTitle.Position =
    UDim2.fromOffset(18,7)

pageTitle.Size =
    UDim2.new(1,-125,0,28)

pageTitle.BackgroundTransparency = 1

pageTitle.Text =
    "ALL ALBUMS"

pageTitle.TextColor3 =
    Color3.new(1,1,1)

pageTitle.TextSize = 19

pageTitle.Font =
    Enum.Font.GothamBold

pageTitle.TextXAlignment =
    Enum.TextXAlignment.Left

pageTitle.Parent = header

local status =
    Instance.new("TextLabel")

status.Position =
    UDim2.fromOffset(18,34)

status.Size =
    UDim2.new(1,-130,0,20)

status.BackgroundTransparency = 1

status.Text =
    "Scanner starting..."

status.TextColor3 =
    Color3.fromRGB(160,160,160)

status.TextSize = 11

status.Font =
    Enum.Font.Gotham

status.TextXAlignment =
    Enum.TextXAlignment.Left

status.Parent = header

--========================================================
-- SEARCH BUTTON
--========================================================

local searchButton =
    makeButton(
        header,
        "🔍",
        UDim2.fromOffset(44,44),
        UDim2.new(1,-53,0,9)
    )

searchButton.TextSize = 18

--========================================================
-- SEARCH BAR
--========================================================

local searchFrame =
    Instance.new("Frame")

searchFrame.Position =
    UDim2.fromOffset(8,68)

searchFrame.Size =
    UDim2.new(1,-16,0,46)

searchFrame.BackgroundColor3 =
    Color3.fromRGB(17,17,17)

searchFrame.BorderSizePixel = 0

searchFrame.Visible = false

searchFrame.Parent = root

corner(searchFrame,12)

local searchBox =
    Instance.new("TextBox")

searchBox.Position =
    UDim2.fromOffset(12,0)

searchBox.Size =
    UDim2.new(1,-58,1,0)

searchBox.BackgroundTransparency = 1

searchBox.PlaceholderText =
    "Tìm tên người hoặc album..."

searchBox.PlaceholderColor3 =
    Color3.fromRGB(130,130,130)

searchBox.Text = ""

searchBox.TextColor3 =
    Color3.new(1,1,1)

searchBox.TextSize = 14

searchBox.Font =
    Enum.Font.Gotham

searchBox.TextXAlignment =
    Enum.TextXAlignment.Left

searchBox.ClearTextOnFocus = false

searchBox.Parent = searchFrame

local clearSearch =
    makeButton(
        searchFrame,
        "×",
        UDim2.fromOffset(38,38),
        UDim2.new(1,-42,.5,-19)
    )

clearSearch.TextSize = 23

--========================================================
-- ALBUM GRID
--========================================================

local albumList =
    Instance.new("ScrollingFrame")

albumList.Position =
    UDim2.fromOffset(7,67)

albumList.Size =
    UDim2.new(1,-14,1,-74)

albumList.BackgroundTransparency = 1

albumList.BorderSizePixel = 0
albumList.ScrollBarThickness = 3

albumList.CanvasSize =
    UDim2.new()

albumList.AutomaticCanvasSize =
    Enum.AutomaticSize.Y

albumList.Parent = root

local grid =
    Instance.new("UIGridLayout")

grid.CellPadding =
    UDim2.fromOffset(7,7)

grid.CellSize =
    UDim2.new(.5,-4,0,225)

grid.SortOrder =
    Enum.SortOrder.LayoutOrder

grid.Parent = albumList

-- Responsive columns

local function updateGrid()

    local width =
        albumList.AbsoluteSize.X

    if width >= 1000 then

        grid.CellSize =
            UDim2.new(.2,-6,0,250)

    elseif width >= 700 then

        grid.CellSize =
            UDim2.new(.25,-6,0,240)

    elseif width >= 500 then

        grid.CellSize =
            UDim2.new(.333,-6,0,230)

    else

        grid.CellSize =
            UDim2.new(.5,-4,0,220)
    end
end

albumList:GetPropertyChangedSignal(
    "AbsoluteSize"
):Connect(updateGrid)

task.defer(updateGrid)

--========================================================
-- VIEWER
--========================================================

local viewer =
    Instance.new("Frame")

viewer.Size =
    UDim2.fromScale(1,1)

viewer.BackgroundColor3 =
    Color3.new(0,0,0)

viewer.BorderSizePixel = 0
viewer.Visible = false

viewer.ZIndex = 20

viewer.Parent = gui

local viewerBack =
    makeButton(
        viewer,
        "‹ ALBUM",
        UDim2.fromOffset(92,42),
        UDim2.fromOffset(8,8)
    )

viewerBack.ZIndex = 30

--========================================================
-- CREATOR BUTTON
--========================================================

local creatorButton =
    makeButton(
        viewer,
        "",
        UDim2.new(1,-220,0,42),
        UDim2.new(0,110,0,8)
    )

creatorButton.ZIndex = 30

local creatorHint =
    Instance.new("TextLabel")

creatorHint.AnchorPoint =
    Vector2.new(.5,0)

creatorHint.Position =
    UDim2.new(.5,0,0,53)

creatorHint.Size =
    UDim2.fromOffset(200,18)

creatorHint.BackgroundTransparency = 1

creatorHint.Text =
    "bấm tên để xem tất cả album"

creatorHint.TextColor3 =
    Color3.fromRGB(150,150,150)

creatorHint.TextSize = 10

creatorHint.Font =
    Enum.Font.Gotham

creatorHint.ZIndex = 30

creatorHint.Parent = viewer

--========================================================
-- IMAGE
--========================================================

local photo =
    Instance.new("ImageButton")

photo.AnchorPoint =
    Vector2.new(.5,.5)

photo.Position =
    UDim2.new(.5,0,.5,20)

photo.Size =
    UDim2.new(1,-10,1,-130)

photo.BackgroundTransparency = 1
photo.AutoButtonColor = false

photo.ScaleType =
    Enum.ScaleType.Fit

photo.Active = true

photo.ZIndex = 21

photo.Parent = viewer

local loading =
    Instance.new("TextLabel")

loading.AnchorPoint =
    Vector2.new(.5,.5)

loading.Position =
    UDim2.fromScale(.5,.5)

loading.Size =
    UDim2.fromOffset(220,60)

loading.BackgroundTransparency = 1

loading.Text =
    "Đang tải..."

loading.TextColor3 =
    Color3.new(1,1,1)

loading.TextSize = 15

loading.Font =
    Enum.Font.GothamBold

loading.ZIndex = 25

loading.Parent = viewer

--========================================================
-- PREV / NEXT
--========================================================

local previous =
    makeButton(
        viewer,
        "‹",
        UDim2.fromOffset(48,72),
        UDim2.new(0,8,.5,-36)
    )

previous.TextSize = 34
previous.ZIndex = 30

local nextButton =
    makeButton(
        viewer,
        "›",
        UDim2.fromOffset(48,72),
        UDim2.new(1,-56,.5,-36)
    )

nextButton.TextSize = 34
nextButton.ZIndex = 30

local counter =
    Instance.new("TextLabel")

counter.AnchorPoint =
    Vector2.new(.5,1)

counter.Position =
    UDim2.new(.5,0,1,-12)

counter.Size =
    UDim2.fromOffset(180,36)

counter.BackgroundColor3 =
    Color3.fromRGB(14,14,14)

counter.BackgroundTransparency = .15

counter.BorderSizePixel = 0

counter.TextColor3 =
    Color3.new(1,1,1)

counter.TextSize = 14

counter.Font =
    Enum.Font.GothamBold

counter.ZIndex = 30

counter.Parent = viewer

corner(counter,12)

--========================================================
-- FULL IMAGE + PINCH ZOOM
--========================================================

local imageZoomed = false
local zoomScale = 1
local pinchStartScale = 1
local pinchActive = false

local panX = 0
local panY = 0
local panInput = nil
local panStart = nil
local panStartX = 0
local panStartY = 0

local MIN_ZOOM = 1
local MAX_ZOOM = 6

local zoomClose =
    makeButton(
        viewer,
        "×",
        UDim2.fromOffset(48,48),
        UDim2.new(1,-58,0,10)
    )

zoomClose.TextSize = 30
zoomClose.ZIndex = 60
zoomClose.Visible = false

local function clampPan()

    if zoomScale <= 1 then
        panX = 0
        panY = 0
        return
    end

    local size = viewer.AbsoluteSize

    local maxX =
        math.max(0, size.X * (zoomScale - 1) * 0.5)

    local maxY =
        math.max(0, size.Y * (zoomScale - 1) * 0.5)

    panX = math.clamp(panX, -maxX, maxX)
    panY = math.clamp(panY, -maxY, maxY)
end

local function applyImageTransform()

    if not imageZoomed then
        return
    end

    zoomScale =
        math.clamp(zoomScale, MIN_ZOOM, MAX_ZOOM)

    clampPan()

    -- At 1x the image is simply full-screen + Fit.
    -- Pinch makes this box larger, which really magnifies the image.
    photo.Size =
        UDim2.fromScale(zoomScale, zoomScale)

    photo.Position =
        UDim2.new(.5, panX, .5, panY)
end

local function resetImageTransform()

    zoomScale = 1
    pinchStartScale = 1
    pinchActive = false

    panX = 0
    panY = 0
    panInput = nil
    panStart = nil
end

local function setImageZoom(enabled)

    imageZoomed = enabled == true

    resetImageTransform()

    if imageZoomed then

        -- Open full-screen at 1x, preserving the whole image.
        photo.Position =
            UDim2.fromScale(.5,.5)

        photo.Size =
            UDim2.fromScale(1,1)

        photo.ScaleType =
            Enum.ScaleType.Fit

        photo.ZIndex = 40

        -- Hide all viewer controls. Only × remains.
        viewerBack.Visible = false
        creatorButton.Visible = false
        creatorHint.Visible = false
        previous.Visible = false
        nextButton.Visible = false
        counter.Visible = false

        zoomClose.Visible = true

    else

        photo.Position =
            UDim2.new(.5,0,.5,20)

        photo.Size =
            UDim2.new(1,-10,1,-130)

        photo.ScaleType =
            Enum.ScaleType.Fit

        photo.ZIndex = 21

        viewerBack.Visible = true
        creatorButton.Visible = true
        creatorHint.Visible = true
        previous.Visible = true
        nextButton.Visible = true
        counter.Visible = true

        zoomClose.Visible = false
    end
end

zoomClose.MouseButton1Click:Connect(function()
    setImageZoom(false)
end)

-- One tap: enter full-screen image mode.
photo.Activated:Connect(function()
    if not imageZoomed then
        setImageZoom(true)
    end
end)

-- Two-finger pinch: zoom 1x -> 6x.
UIS.TouchPinch:Connect(function(
    touchPositions,
    scale,
    velocity,
    state,
    gameProcessedEvent
)

    if not imageZoomed then
        return
    end

    if state == Enum.UserInputState.Begin then

        pinchActive = true
        pinchStartScale = zoomScale
        panInput = nil
        panStart = nil

    elseif state == Enum.UserInputState.Change then

        pinchActive = true

        local gestureScale = tonumber(scale) or 1

        zoomScale =
            math.clamp(
                pinchStartScale * gestureScale,
                MIN_ZOOM,
                MAX_ZOOM
            )

        if zoomScale <= 1.001 then
            panX = 0
            panY = 0
        end

        applyImageTransform()

    elseif state == Enum.UserInputState.End
    or state == Enum.UserInputState.Cancel then

        pinchActive = false
        pinchStartScale = zoomScale
    end
end)

-- When zoomed in, drag with one finger / mouse to pan around the image.
photo.InputBegan:Connect(function(input)

    if not imageZoomed
    or zoomScale <= 1
    or pinchActive then
        return
    end

    if input.UserInputType ~= Enum.UserInputType.Touch
    and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
        return
    end

    panInput = input
    panStart = input.Position
    panStartX = panX
    panStartY = panY
end)

UIS.InputChanged:Connect(function(input)

    if not imageZoomed
    or not panInput
    or not panStart
    or pinchActive then
        return
    end

    if input ~= panInput then
        return
    end

    local delta =
        input.Position - panStart

    panX = panStartX + delta.X
    panY = panStartY + delta.Y

    applyImageTransform()
end)

UIS.InputEnded:Connect(function(input)

    if input == panInput then
        panInput = nil
        panStart = nil
    end
end)

--========================================================
-- CARDS
--========================================================

local albumCards = {}

local refreshAlbumGrid

local function createAlbumCard(index)

    local album =
        ALBUMS[index]

    if not album then
        return
    end

    local card =
        Instance.new("ImageButton")

    card.Name =
        "Album_" .. index

    card.BackgroundColor3 =
        Color3.fromRGB(20,20,20)

    card.BorderSizePixel = 0

    card.ScaleType =
        Enum.ScaleType.Crop

    card.AutoButtonColor = false

    card.LayoutOrder = index

    card.Parent = albumList

    corner(card,13)

    albumCards[index] = card

    -- Dark bottom gradient-like overlay

    local overlay =
        Instance.new("Frame")

    overlay.AnchorPoint =
        Vector2.new(0,1)

    overlay.Position =
        UDim2.fromScale(0,1)

    overlay.Size =
        UDim2.new(1,0,0,78)

    overlay.BackgroundColor3 =
        Color3.fromRGB(0,0,0)

    overlay.BackgroundTransparency =
        .25

    overlay.BorderSizePixel = 0

    overlay.ZIndex = 2

    overlay.Parent = card

    corner(overlay,13)

    local creator =
        Instance.new("TextLabel")

    creator.Position =
        UDim2.fromOffset(9,7)

    creator.Size =
        UDim2.new(1,-18,0,20)

    creator.BackgroundTransparency = 1

    creator.Text =
        album.Creator

    creator.TextColor3 =
        Color3.fromRGB(210,210,210)

    creator.TextSize = 11

    creator.Font =
        Enum.Font.GothamBold

    creator.TextXAlignment =
        Enum.TextXAlignment.Left

    creator.TextTruncate =
        Enum.TextTruncate.AtEnd

    creator.ZIndex = 3

    creator.Parent = overlay

    local name =
        Instance.new("TextLabel")

    name.Position =
        UDim2.fromOffset(9,27)

    name.Size =
        UDim2.new(1,-18,0,31)

    name.BackgroundTransparency = 1

    name.Text =
        album.Name

    name.TextColor3 =
        Color3.new(1,1,1)

    name.TextSize = 12

    name.Font =
        Enum.Font.GothamBold

    name.TextWrapped = true

    name.TextXAlignment =
        Enum.TextXAlignment.Left

    name.TextYAlignment =
        Enum.TextYAlignment.Top

    name.ZIndex = 3

    name.Parent = overlay

    local count =
        Instance.new("TextLabel")

    count.AnchorPoint =
        Vector2.new(0,1)

    count.Position =
        UDim2.new(0,9,1,-5)

    count.Size =
        UDim2.new(1,-18,0,15)

    count.BackgroundTransparency = 1

    count.Text =
        #album.Images .. " ảnh"

    count.TextColor3 =
        Color3.fromRGB(170,170,170)

    count.TextSize = 10

    count.Font =
        Enum.Font.Gotham

    count.TextXAlignment =
        Enum.TextXAlignment.Left

    count.ZIndex = 3

    count.Parent = overlay

    -- Cover background load

    task.spawn(function()

        local cover =
            album.Images[1]

        if not cover then
            return
        end

        local asset =
            downloadImage(cover)

        if card.Parent and asset then
            card.Image = asset
        end
    end)

    card.MouseButton1Click:Connect(function()

        currentAlbumIndex = index
        currentImageIndex = 1

        returnMode = currentMode
        returnCreator = currentCreator

        setImageZoom(false)

        viewer.Visible = true
        root.Visible = false

        photo.Image = ""

        local selected =
            ALBUMS[currentAlbumIndex]

        creatorButton.Text =
            selected.Creator

        imageToken += 1

        local myToken =
            imageToken

        loading.Visible = true
        loading.Text = "Đang tải..."

        counter.Text =
            "1 / " .. #selected.Images

        task.spawn(function()

            local asset =
                downloadImage(
                    selected.Images[1]
                )

            if myToken ~= imageToken then
                return
            end

            if asset then

                photo.Image = asset
                loading.Visible = false

            else

                loading.Visible = true
                loading.Text = "Ảnh lỗi"
            end
        end)
    end)
end

--========================================================
-- FILTER GRID
--========================================================

refreshAlbumGrid = function()

    local query =
        normalizeSearch(
            searchBox.Text
        )

    for index,card in pairs(albumCards) do

        local album =
            ALBUMS[index]

        if album and card then

            local allowed = true

            if currentMode == "creator" then

                allowed =
                    normalizeSearch(album.Creator)
                    ==
                    normalizeSearch(currentCreator)
            end

            if allowed
            and query ~= "" then

                local haystack =
                    normalizeSearch(
                        album.Name
                        .. " "
                        .. album.Creator
                    )

                allowed =
                    haystack:find(
                        query,
                        1,
                        true
                    ) ~= nil
            end

            card.Visible = allowed
        end
    end
end

--========================================================
-- SEARCH
--========================================================

searchButton.MouseButton1Click:Connect(function()

    searchFrame.Visible =
        not searchFrame.Visible

    if searchFrame.Visible then

        albumList.Position =
            UDim2.fromOffset(7,121)

        albumList.Size =
            UDim2.new(1,-14,1,-128)

        task.defer(function()
            searchBox:CaptureFocus()
        end)

    else

        searchBox.Text = ""

        albumList.Position =
            UDim2.fromOffset(7,67)

        albumList.Size =
            UDim2.new(1,-14,1,-74)
    end

    refreshAlbumGrid()
end)

clearSearch.MouseButton1Click:Connect(function()

    searchBox.Text = ""
end)

searchBox:GetPropertyChangedSignal(
    "Text"
):Connect(function()

    refreshAlbumGrid()
end)

--========================================================
-- CREATOR PAGE
--========================================================

local function showCreator(creator)

    viewer.Visible = false
    root.Visible = true

    currentMode = "creator"
    currentCreator = creator

    pageTitle.Text = creator

    backButton.Visible = true

    searchBox.Text = ""

    refreshAlbumGrid()

    albumList.CanvasPosition =
        Vector2.zero
end

creatorButton.MouseButton1Click:Connect(function()

    if not currentAlbumIndex then
        return
    end

    local album =
        ALBUMS[currentAlbumIndex]

    if not album then
        return
    end

    showCreator(
        album.Creator
    )
end)

--========================================================
-- CREATOR BACK
--========================================================

backButton.MouseButton1Click:Connect(function()

    currentMode = "all"
    currentCreator = nil

    pageTitle.Text =
        "ALL ALBUMS"

    backButton.Visible = false

    searchBox.Text = ""

    refreshAlbumGrid()

    albumList.CanvasPosition =
        Vector2.zero
end)

--========================================================
-- PRELOAD
--========================================================

local function preloadAround(album,index)

    if not PRELOAD_IMAGES then
        return
    end

    task.spawn(function()

        local total =
            #album.Images

        if total <= 1 then
            return
        end

        local indexes = {
            index + 1,
            index - 1,
            index + 2
        }

        for _,i in ipairs(indexes) do

            if i > total then
                i = i - total
            end

            if i < 1 then
                i = total + i
            end

            local url =
                album.Images[i]

            if url
            and not assetCache[url] then

                downloadImage(url)
            end
        end
    end)
end

--========================================================
-- DISPLAY CURRENT IMAGE
--========================================================

local function displayCurrentImage()

    local album =
        ALBUMS[currentAlbumIndex]

    if not album then
        return
    end

    local url =
        album.Images[currentImageIndex]

    if not url then
        return
    end

    imageToken += 1

    local token =
        imageToken

    counter.Text =
        currentImageIndex
        .. " / "
        .. #album.Images

    creatorButton.Text =
        album.Creator

    if assetCache[url] then

        photo.Image =
            assetCache[url]

        loading.Visible = false

        preloadAround(
            album,
            currentImageIndex
        )

        return
    end

    loading.Visible = true
    loading.Text = "Đang tải..."

    task.spawn(function()

        local asset =
            downloadImage(url)

        if token ~= imageToken then
            return
        end

        if asset then

            photo.Image = asset
            loading.Visible = false

            preloadAround(
                album,
                currentImageIndex
            )

        else

            loading.Visible = true
            loading.Text = "Ảnh lỗi"
        end
    end)
end

--========================================================
-- NEXT
--========================================================

nextButton.MouseButton1Click:Connect(function()

    local album =
        ALBUMS[currentAlbumIndex]

    if not album then
        return
    end

    currentImageIndex += 1

    if currentImageIndex >
        #album.Images then

        currentImageIndex = 1
    end

    displayCurrentImage()
end)

--========================================================
-- PREVIOUS
--========================================================

previous.MouseButton1Click:Connect(function()

    local album =
        ALBUMS[currentAlbumIndex]

    if not album then
        return
    end

    currentImageIndex -= 1

    if currentImageIndex < 1 then

        currentImageIndex =
            #album.Images
    end

    displayCurrentImage()
end)

--========================================================
-- BACK FROM VIEWER
--========================================================

viewerBack.MouseButton1Click:Connect(function()

    setImageZoom(false)

    imageToken += 1

    viewer.Visible = false
    root.Visible = true

    photo.Image = ""

    currentMode =
        returnMode or "all"

    currentCreator =
        returnCreator

    if currentMode == "creator"
    and currentCreator then

        pageTitle.Text =
            currentCreator

        backButton.Visible = true

    else

        currentMode = "all"
        currentCreator = nil

        pageTitle.Text =
            "ALL ALBUMS"

        backButton.Visible = false
    end

    refreshAlbumGrid()
end)

--========================================================
-- SWIPE
--========================================================

local swipeStart = nil

photo.InputBegan:Connect(function(input)

    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1 then

        swipeStart = input.Position
    end
end)

photo.InputEnded:Connect(function(input)

    if input.UserInputType ~= Enum.UserInputType.Touch
    and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
        return
    end

    if not swipeStart then
        return
    end

    local delta =
        input.Position - swipeStart

    swipeStart = nil

    -- In full-image mode the close button is the only exit control.
    if imageZoomed then
        return
    end

    -- Taps are handled by photo.Activated above.
    -- Horizontal swipe changes image as before.
    if math.abs(delta.X) < 55
    or math.abs(delta.X) <= math.abs(delta.Y) then
        return
    end

    local album =
        ALBUMS[currentAlbumIndex]

    if not album then
        return
    end

    if delta.X < 0 then

        currentImageIndex += 1

        if currentImageIndex >
            #album.Images then

            currentImageIndex = 1
        end

    else

        currentImageIndex -= 1

        if currentImageIndex < 1 then

            currentImageIndex =
                #album.Images
        end
    end

    displayCurrentImage()
end)

--========================================================
-- SCANNER STATE
--========================================================

local scannedPosts = {}

local foundAlbums = 0
local scannedPostsCount = 0

local scannerFinished = false

local function updateStatus(extra)

    if not gui.Parent then
        return
    end

    if scannerFinished then

        status.Text =
            foundAlbums
            .. " album • "
            .. scannedPostsCount
            .. " bài"

        return
    end

    status.Text =
        "● "
        .. foundAlbums
        .. " album • "
        .. scannedPostsCount
        .. " bài"

    if extra then
        status.Text ..= " • " .. extra
    end
end

--========================================================
-- PROCESS POST
--========================================================

local function processPost(post)

    if not gui.Parent then
        return
    end

    if scannedPosts[post.URL] then
        return
    end

    scannedPosts[post.URL] = true

    scannedPostsCount += 1

    updateStatus("quét ngầm")

    local html =
        requestURL(post.URL)

    if not html then
        return
    end

    local images =
        parseImages(html)

    if #images < 2 then
        return
    end

    if albumURLSeen[post.URL] then
        return
    end

    albumURLSeen[post.URL] = true

    local creator =
        creatorFromAlbum(
            html,
            post.Name,
            post.URL
        )

    local index =
        #ALBUMS + 1

    ALBUMS[index] = {
        Name = post.Name,
        Creator = creator,
        URL = post.URL,
        Images = images
    }

    foundAlbums += 1

    createAlbumCard(index)

    refreshAlbumGrid()

    updateStatus("quét ngầm")
end

--========================================================
-- WORKERS
--========================================================

local function scanPosts(posts)

    if #posts == 0 then
        return
    end

    local cursor = 1
    local workersFinished = 0

    local workerCount =
        math.min(
            SCAN_WORKERS,
            #posts
        )

    for _ = 1,workerCount do

        task.spawn(function()

            while gui.Parent do

                if MAX_ALBUMS > 0
                and foundAlbums >= MAX_ALBUMS then
                    break
                end

                local index = cursor
                cursor += 1

                local post =
                    posts[index]

                if not post then
                    break
                end

                processPost(post)

                task.wait(
                    REQUEST_DELAY
                )
            end

            workersFinished += 1
        end)
    end

    while gui.Parent
    and workersFinished < workerCount do

        task.wait(.05)
    end
end

--========================================================
-- SCAN SOURCE
--========================================================

local function scanSource(baseURL)

    if baseURL:sub(-1) ~= "/" then
        baseURL ..= "/"
    end

    for page = 1,MAX_PAGES do

        if not gui.Parent then
            return
        end

        if MAX_ALBUMS > 0
        and foundAlbums >= MAX_ALBUMS then
            return
        end

        local pageURL

        if page == 1 then

            pageURL =
                baseURL

        else

            pageURL =
                baseURL
                .. "page/"
                .. page
                .. "/"
        end

        updateStatus(
            "trang "
            .. page
            .. "/"
            .. MAX_PAGES
        )

        local html =
            requestURL(pageURL)

        if not html then

            warn(
                "[ALBUM] Failed:",
                pageURL
            )

            continue
        end

        local posts =
            parsePostLinks(html)

        print(
            "[ALBUM] Page",
            page,
            "=",
            #posts,
            "posts"
        )

        if #posts == 0 then
            break
        end

        scanPosts(posts)

        task.wait(.12)
    end
end

--========================================================
-- START BACKGROUND SCANNER
--========================================================

task.spawn(function()

    status.Text =
        "● Đang quét..."

    for _,source in ipairs(
        SCAN_PAGES
    ) do

        if not gui.Parent then
            return
        end

        scanSource(source)

        if MAX_ALBUMS > 0
        and foundAlbums >= MAX_ALBUMS then
            break
        end
    end

    scannerFinished = true

    updateStatus()

    print(
        "[ALBUM] COMPLETE:",
        foundAlbums
    )
end)

--========================================================
-- FLOATING TOGGLE
--========================================================

local toggle =
    Instance.new("TextButton")

toggle.Size =
    UDim2.fromOffset(48,48)

toggle.Position =
    UDim2.new(
        0,12,
        .5,-24
    )

toggle.BackgroundColor3 =
    Color3.fromRGB(15,15,15)

toggle.BackgroundTransparency =
    .08

toggle.BorderSizePixel = 0

toggle.Text = "□"

toggle.TextColor3 =
    Color3.new(1,1,1)

toggle.TextSize = 27

toggle.Font =
    Enum.Font.GothamBold

toggle.Parent = toggleGui

corner(toggle,11)

local stroke =
    Instance.new("UIStroke")

stroke.Color =
    Color3.fromRGB(220,220,220)

stroke.Transparency = .45

stroke.Thickness = 1

stroke.Parent = toggle

--========================================================
-- TOGGLE DRAG / CLICK
--========================================================

local dragging = false
local moved = false

local dragStart = nil
local startPosition = nil

toggle.InputBegan:Connect(function(input)

    if input.UserInputType ~=
        Enum.UserInputType.MouseButton1
    and input.UserInputType ~=
        Enum.UserInputType.Touch then
        return
    end

    dragging = true
    moved = false

    dragStart =
        input.Position

    startPosition =
        toggle.Position
end)

UIS.InputChanged:Connect(function(input)

    if not dragging then
        return
    end

    if input.UserInputType ~=
        Enum.UserInputType.MouseMovement
    and input.UserInputType ~=
        Enum.UserInputType.Touch then
        return
    end

    local delta =
        input.Position
        - dragStart

    if math.abs(delta.X) > 5
    or math.abs(delta.Y) > 5 then

        moved = true
    end

    toggle.Position =
        UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset
                + delta.X,

            startPosition.Y.Scale,
            startPosition.Y.Offset
                + delta.Y
        )
end)

UIS.InputEnded:Connect(function(input)

    if not dragging then
        return
    end

    if input.UserInputType ~=
        Enum.UserInputType.MouseButton1
    and input.UserInputType ~=
        Enum.UserInputType.Touch then
        return
    end

    dragging = false

    if moved then
        return
    end

    gui.Enabled =
        not gui.Enabled

    if gui.Enabled then

        toggle.Text = "□"
        toggle.BackgroundTransparency = .08

    else

        toggle.Text = "■"
        toggle.BackgroundTransparency = .25
    end
end)

print("======================================")
print("COSPLAY ALBUM V4 READY")
print("Full page: ON")
print("Search: ON")
print("Creator albums: ON")
print("Background scan: ON")
print("Cache/retry/preload: ON")
print("======================================")
