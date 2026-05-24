-- CapsLock は hidutil で F20 (keycode=90) にリマップ済み
-- GC で破棄されないようグローバル変数で保持する
_hyperModal = hs.hotkey.modal.new()

-- F20 keyDown → Hyper ON, keyUp → Hyper OFF
_f20Hotkey = hs.hotkey.bind({}, "f20",
    function() _hyperModal:enter() end,
    function() _hyperModal:exit() end
)

-- ウィンドウ中央にマウスカーソルを移動する
local function moveMouseToCenter(win)
    local frame = win:frame()
    hs.mouse.absolutePosition({
        x = frame.x + frame.w / 2,
        y = frame.y + frame.h / 2,
    })
end

-- 内蔵ディスプレイの取得（regex match 回避のため cache 化）
_builtInScreenCache = nil
local function getBuiltInScreen()
    if _builtInScreenCache then return _builtInScreenCache end
    for _, s in ipairs(hs.screen.allScreens()) do
        local name = s:name() or ""
        if name:match("Built[- ]?[Ii]n") or name:match("Color LCD") or name:match("Liquid Retina") then
            _builtInScreenCache = s
            return s
        end
    end
    _builtInScreenCache = hs.screen.primaryScreen()
    return _builtInScreenCache
end

-- モニタ構成変更で cache 無効化
_screenWatcher = hs.screen.watcher.new(function() _builtInScreenCache = nil end)
_screenWatcher:start()

-- window ID → "B"(Built-in) or "E"(External)
-- live w:screen() が non-nil の時のみ書き込み、cross-Space コンテキストでも target 判定に使える
_winMonitor = {}

-- focusAppOnMonitor を使うアプリの集合（_winMonitor 更新は活性化時にこれだけ走らせる）
_monitorApps = { ["com.vivaldi.Vivaldi"] = true }

-- live w:screen() が non-nil なら _winMonitor を更新する
local function noteMonitor(w, id, builtIn)
    if not id then return end
    local sc = w:screen()
    if not sc then return end
    _winMonitor[id] = (sc:id() == builtIn:id()) and "B" or "E"
end

-- bundleID → { B = lastFocusedIDOnBuiltIn, E = lastFocusedIDOnExternal }
-- user が実際に focus した window のみ記録（system window を target 候補から排除する）
_lastWindowPerMonitor = {}

local function rememberLastPerMonitor(bid, id, key)
    if not (bid and id and key) then return end
    _lastWindowPerMonitor[bid] = _lastWindowPerMonitor[bid] or {}
    _lastWindowPerMonitor[bid][key] = id
end

-- bundleID でインデックスしたウィンドウキャッシュ
-- hs.window.filter / hs.spaces は macOS 26 でプライベート API モーダルが発生するため不使用
-- hs.application.watcher（NSWorkspace 公開 API）でアプリ切り替え時にキャッシュを更新する
_bundleCache = {}

-- bundleID ごとの最後にフォーカスしたウィンドウ ID（戻り先の起点）
_lastWindow = {}

-- AX にウィンドウが無いと判明した bundleID（次回スキャン省略のヒント）
-- activated 時に app:allWindows() が >0 を返したらクリア
_knownEmpty = {}

-- 起動時 1 回だけ全ウィンドウをキャッシュに取り込む
local _startupBI = getBuiltInScreen()
for _, w in ipairs(hs.window.allWindows()) do
    local id = w:id()
    local a = w:application()
    if id and a then
        local bid = a:bundleID()
        if bid then
            _bundleCache[bid] = _bundleCache[bid] or {}
            _bundleCache[bid][id] = w
            if _monitorApps[bid] then noteMonitor(w, id, _startupBI) end
        end
    end
end

-- アプリが活性化したときにそのアプリのキャッシュだけ更新（全ウィンドウスキャン回避）
_appWatcher = hs.application.watcher.new(function(_, event, app)
    if event ~= hs.application.watcher.activated then return end
    local bid = app:bundleID()
    if not bid then return end
    local bucket = _bundleCache[bid] or {}
    _bundleCache[bid] = bucket
    local found = false
    for _, w in ipairs(app:allWindows()) do
        local id = w:id()
        if id then bucket[id] = w; found = true end
    end
    local isMon = _monitorApps[bid] == true
    local bi = isMon and getBuiltInScreen() or nil
    -- focused が活性化アプリのウィンドウなら必ずキャッシュに追加（app:allWindows が cross-Space で漏らした場合の保険）
    local fw = hs.window.focusedWindow()
    if fw then
        local fapp = fw:application()
        local fid = fw:id()
        if fid and fapp and fapp:bundleID() == bid then
            bucket[fid] = fw
            _lastWindow[bid] = fid
            found = true
            if isMon then
                noteMonitor(fw, fid, bi)  -- ② live で必ず取れる
                local mon = _winMonitor[fid]
                if mon then rememberLastPerMonitor(bid, fid, mon) end
            end
        end
    end
    if found then _knownEmpty[bid] = nil end
    -- ③ opportunistic: monitorApps の cached window を毎回試行・常時上書き
    -- （window が別モニタへ移動した場合の追従。screen() が nil なら何もしないので無害）
    if isMon then
        for id, w in pairs(bucket) do
            noteMonitor(w, id, bi)
        end
    end
end)
_appWatcher:start()

-- ウィンドウが生きているかつサイクル対象として有効かを判定する（AX 呼び出し 1 回）
-- 閉じたウィンドウは pcall(w:title) が失敗または nil
-- タイトル有り → 通過（Vivaldi 含む）
-- タイトル空 → 大サイズなら通過（Ghostty）、小さければ除外（Obsidian transient）
local function isAliveAndCyclable(w)
    local ok, title = pcall(function() return w:title() end)
    if not ok or title == nil then return false end
    if title ~= "" then return true end
    local okF, frame = pcall(function() return w:frame() end)
    return okF and frame and frame.w > 400 and frame.h > 300
end

-- target 単体が生きているかを判定する（focusApp 非サイクル分岐用）
local function isAlive(w)
    local ok, title = pcall(function() return w:title() end)
    return ok and title ~= nil
end

-- bundle ID に一致するウィンドウを取得する（全 Space 対応、最新 ID 降順）
-- 高速化のため isAlive チェックは行わない（呼び出し側で target 検証する）
-- isStandard() は Vivaldi 等を誤って除外するため使わない
local function getWindowsByBundleID(bundleID)
    local result = {}

    if _bundleCache[bundleID] then
        for _, w in pairs(_bundleCache[bundleID]) do
            result[#result + 1] = w
        end
    end

    -- 結果が空 かつ 「無いと判明した」ヒントが無いときだけスキャン
    if #result == 0 and not _knownEmpty[bundleID] then
        local bucket
        -- まず app:allWindows()（高速、AX 非公開アプリは即 0）
        for _, app in ipairs(hs.application.applicationsForBundleID(bundleID)) do
            for _, w in ipairs(app:allWindows()) do
                local id = w:id()
                if id then
                    bucket = bucket or {}
                    bucket[id] = w
                    result[#result + 1] = w
                end
            end
        end
        -- それでも空なら hs.window.allWindows() で cross-monitor を探す（Vivaldi 等）
        if #result == 0 then
            for _, w in ipairs(hs.window.allWindows()) do
                local a = w:application()
                if a and a:bundleID() == bundleID then
                    local id = w:id()
                    if id then
                        bucket = bucket or {}
                        bucket[id] = w
                        result[#result + 1] = w
                    end
                end
            end
        end
        if bucket then
            _bundleCache[bundleID] = bucket
        else
            _knownEmpty[bundleID] = true  -- 両方 0 → 次回スキャン省略
        end
    end

    if #result > 1 then
        table.sort(result, function(a, b) return a:id() > b:id() end)
    end
    return result
end

-- アプリをフォーカスし、マウスをウィンドウ中央へ移動する
-- 既にフォーカス中なら同アプリの次ウィンドウへサイクル
-- 別アプリから戻る場合は _lastWindow を起点に復帰
local function focusApp(bundleID)
    local focused = hs.window.focusedWindow()
    local focusedID = focused and focused:id() or nil
    local focusedApp = focused and focused:application() or nil
    local focusedBID = focusedApp and focusedApp:bundleID() or nil

    -- source 記録（離れる前の focused ウィンドウを記憶）
    if focusedID and focusedBID then _lastWindow[focusedBID] = focusedID end

    local isCycling = focusedBID == bundleID

    -- focused がキャッシュに無いときだけ再スキャン（新規ウィンドウ作成等）
    if isCycling then
        local bucket = _bundleCache[bundleID]
        if not (bucket and bucket[focusedID]) then
            bucket = bucket or {}
            _bundleCache[bundleID] = bucket
            for _, w in ipairs(hs.window.allWindows()) do
                local a = w:application()
                if a and a:bundleID() == bundleID then
                    local id = w:id()
                    if id then bucket[id] = w end
                end
            end
            for _, app in ipairs(hs.application.applicationsForBundleID(bundleID)) do
                for _, w in ipairs(app:allWindows()) do
                    local id = w:id()
                    if id then bucket[id] = w end
                end
            end
        end
    end

    local wins = getWindowsByBundleID(bundleID)

    if #wins == 0 then
        hs.application.launchOrFocusByBundleID(bundleID)
        return
    end

    local target

    if isCycling then
        -- transient + 死ウィンドウを除外（filter 後が空ならフォールバック）
        local cyclable = {}
        for _, w in ipairs(wins) do
            if isAliveAndCyclable(w) then cyclable[#cyclable + 1] = w end
        end
        if #cyclable > 0 then wins = cyclable end

        local currentIdx = 1
        for i, w in ipairs(wins) do
            if w:id() == focusedID then currentIdx = i; break end
        end
        target = wins[(currentIdx % #wins) + 1]
    else
        -- 別アプリから → _lastWindow を起点に復帰
        local lastID = _lastWindow[bundleID]
        if lastID then
            for _, w in ipairs(wins) do
                if w:id() == lastID then target = w; break end
            end
        end
        target = target or wins[1]
        if not isAlive(target) then
            local deadID = target:id()
            _bundleCache[bundleID][deadID] = nil
            _winMonitor[deadID] = nil
            target = nil
            for _, w in ipairs(wins) do
                if isAlive(w) then target = w; break end
            end
            if not target then
                hs.application.launchOrFocusByBundleID(bundleID)
                return
            end
        end
    end

    _lastWindow[bundleID] = target:id()
    target:focus()
    moveMouseToCenter(target)
end

-- 指定アプリを特定モニターにフォーカスする（targetBuiltIn=true で本体、false で外部）
-- _winMonitor で覚えている (windowID → "B"|"E") を主要な手がかりに、
-- cross-Space ウィンドウ（w:screen() が nil を返す）でも target を確定できる
local function focusAppOnMonitor(bundleID, targetBuiltIn)
    local focused = hs.window.focusedWindow()
    local focusedApp = focused and focused:application() or nil
    local focusedBID = focusedApp and focusedApp:bundleID() or nil
    local focusedID = focused and focused:id() or nil

    if focusedID and focusedBID then _lastWindow[focusedBID] = focusedID end

    local builtIn = getBuiltInScreen()
    local key = targetBuiltIn and "B" or "E"
    local bucket = _bundleCache[bundleID] or {}
    _bundleCache[bundleID] = bucket

    -- focused が対象アプリなら必ず cache + _winMonitor 更新（live で取れる）
    if focusedID and focusedBID == bundleID then
        bucket[focusedID] = focused
        noteMonitor(focused, focusedID, builtIn)
    end

    -- 軽量リフレッシュ: 同 Space で新規 window が増えた場合に拾う
    -- （cross-Space window は app:allWindows でも返らないことが多いので activated 経由に任せる）
    for _, app in ipairs(hs.application.applicationsForBundleID(bundleID)) do
        for _, w in ipairs(app:allWindows()) do
            local id = w:id()
            if id then bucket[id] = w end
        end
    end

    -- bucket 空 → アプリ起動 or alert
    if next(bucket) == nil then
        local apps = hs.application.applicationsForBundleID(bundleID)
        if apps and #apps > 0 then
            local label = targetBuiltIn and "本体モニター" or "外部ディスプレイ"
            hs.alert.show("Vivaldi: " .. label .. "にウィンドウが見つかりません")
        else
            hs.application.launchOrFocusByBundleID(bundleID)
        end
        return
    end

    local target = nil

    -- Path 1: 同モニタの last user-focused window を最優先
    -- 整合性 3 条件（exists + alive + _winMonitor 一致）満たすときだけ採用
    local mt = _lastWindowPerMonitor[bundleID]
    local lastID = mt and mt[key]
    if lastID then
        local w = bucket[lastID]
        if not w or not isAlive(w) then
            -- 死亡: 全 cleanup
            if mt then mt[key] = nil end
            bucket[lastID] = nil
            _winMonitor[lastID] = nil
        elseif _winMonitor[lastID] ~= key then
            -- 整合性不一致（user が別モニタへ移動した）: _lastWindowPerMonitor のみ消す
            mt[key] = nil
        else
            target = w
        end
    end

    -- Path 2: bucket を ID 降順、title 有り → 空の 2 段優先
    -- 2a: title 非空（hidden / system window を回避）
    -- 2b: 2a で見つからなければ title 空でも採用（cross-Space で title 空のフォールバック）
    if not target then
        local ids = {}
        for id in pairs(bucket) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b) return a > b end)
        local function tryPick(id, requireTitle)
            local w = bucket[id]
            local mon = _winMonitor[id]
            if mon == nil then
                local sc = w:screen()
                if sc then
                    mon = (sc:id() == builtIn:id()) and "B" or "E"
                    _winMonitor[id] = mon
                end
            end
            if mon ~= key then return nil end
            local okT, title = pcall(function() return w:title() end)
            if not okT or title == nil then return nil end
            if requireTitle and title == "" then return nil end
            return w
        end
        for _, id in ipairs(ids) do
            local w = tryPick(id, true)
            if w then target = w; break end
        end
        if not target then
            for _, id in ipairs(ids) do
                local w = tryPick(id, false)
                if w then target = w; break end
            end
        end
    end

    if target then
        local tid = target:id()
        _winMonitor[tid] = key  -- 確定記録
        _lastWindow[bundleID] = tid
        rememberLastPerMonitor(bundleID, tid, key)
        target:focus()
        moveMouseToCenter(target)
    else
        local label = targetBuiltIn and "本体モニター" or "外部ディスプレイ"
        hs.alert.show("Vivaldi: " .. label .. "にウィンドウが見つかりません")
    end
end

-- Hyper + キー のバインド定義
_hyperModal:bind({}, "d", function() focusApp("com.figma.Desktop") end)
_hyperModal:bind({}, "l", function() focusApp("com.anthropic.claudefordesktop") end)
_hyperModal:bind({}, "o", function() focusApp("md.obsidian") end)
_hyperModal:bind({}, "s", function() focusApp("com.tinyspeck.slackmacgap") end)
_hyperModal:bind({}, "t", function() focusApp("com.mitchellh.ghostty") end)
_hyperModal:bind({}, "c", function() focusApp("com.todesktop.230313mzl4w4u92") end)
_hyperModal:bind({}, "b", function() focusAppOnMonitor("com.vivaldi.Vivaldi", true) end)
_hyperModal:bind({}, "w", function() focusAppOnMonitor("com.vivaldi.Vivaldi", false) end)
_hyperModal:bind({}, "r", function() hs.reload() end)

-- デバッグ: focused アプリのキャッシュ詳細、focused が無ければ全キャッシュサマリをクリップボードへ
_hyperModal:bind({}, ";", function()
    local fw = hs.window.focusedWindow()
    local bid = fw and fw:application() and fw:application():bundleID()

    if bid then
        local fsc = fw:screen()
        local lines = {
            "BID: " .. bid,
            "focused id: " .. tostring(fw:id()) .. " screen=" .. (fsc and fsc:name() or "nil"),
        }
        local mt = _lastWindowPerMonitor[bid]
        if mt then
            lines[#lines+1] = string.format("lastPerMonitor: B=%s E=%s",
                tostring(mt.B or "-"), tostring(mt.E or "-"))
        else
            lines[#lines+1] = "lastPerMonitor: (none)"
        end
        local cache = _bundleCache[bid] or {}
        local count = 0
        for id, w in pairs(cache) do
            local sc = w:screen()
            local title = ""
            local okTitle, t = pcall(function() return w:title() end)
            if okTitle and t then title = t end
            lines[#lines+1] = string.format("id=%s alive=%s screen=%s mon=%s title=%q",
                tostring(id), tostring(isAlive(w)), sc and sc:name() or "nil",
                tostring(_winMonitor[id] or "?"), title)
            count = count + 1
        end
        hs.pasteboard.setContents(table.concat(lines, "\n"))
        hs.alert.show("cache: " .. count .. " 件をコピー")
    else
        -- focused 取れない場合: 全 bundle のキャッシュサマリ
        local lines = { "focused なし - 全キャッシュサマリ:" }
        local bids = {}
        for b in pairs(_bundleCache) do bids[#bids+1] = b end
        table.sort(bids)
        for _, b in ipairs(bids) do
            local cnt = 0
            for _ in pairs(_bundleCache[b]) do cnt = cnt + 1 end
            lines[#lines+1] = string.format("%-50s %d", b, cnt)
        end
        -- Ghostty の詳細も追加（あれば）
        local gcache = _bundleCache["com.mitchellh.ghostty"]
        if gcache then
            lines[#lines+1] = ""
            lines[#lines+1] = "Ghostty 詳細:"
            for id, w in pairs(gcache) do
                local title = ""
                local okT, t = pcall(function() return w:title() end)
                if okT and t then title = t end
                lines[#lines+1] = string.format("  id=%s alive=%s title=%q",
                    tostring(id), tostring(isAlive(w)), title)
            end
        end
        hs.pasteboard.setContents(table.concat(lines, "\n"))
        hs.alert.show("全キャッシュをコピー")
    end
end)
