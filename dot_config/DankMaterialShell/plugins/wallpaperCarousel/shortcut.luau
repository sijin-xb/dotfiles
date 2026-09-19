-- Wallpaper Carousel — Control Center shortcut entry.
--
-- A toggle button in Control Center's shortcut grid. It runs in its own Luau
-- runtime (and only while the panel is open), so it does not touch the overlay
-- itself: it asks the service to, through the per-plugin state store. That keeps
-- ownership of the Quickshell child in exactly one place and costs no subprocess.

local function request(action: string)
	noctalia.state.set("command", {
		action = action,
		-- The store notifies watchers on every set, so this is only here to make
		-- the intent legible in logs; repeats do not need to differ.
		at = noctalia.nowMs(),
	})
end

function update()
	-- Polled by the host while the panel is open; the service publishes
	-- "overlayOpen" whenever the overlay's visibility changes.
	shortcut.setLabel(noctalia.tr("shortcut.label"))
	shortcut.setIcon("carousel-horizontal")
	shortcut.setActive(noctalia.state.get("overlayOpen") == true)
end

function onClick()
	request("toggle")
end

function onRightClick()
	noctalia.openSettings()
end
