hs.window.animationDuration = 0

-- ~/.hammerspoon 以下の .lua ファイルを監視して自動リロード
local watcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", function(files)
    local doReload = false
    for _, file in pairs(files) do
        if file:sub(-4) == ".lua" then
            doReload = true
        end
    end
    if doReload then
        hs.reload()
    end
end)
watcher:start()

require("apps")

hs.alert.show("Hammerspoon loaded")
