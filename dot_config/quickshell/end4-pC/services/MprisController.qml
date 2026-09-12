pragma Singleton
pragma ComponentBehavior: Bound

// From https://git.outfoxxed.me/outfoxxed/nixnew
// It does not have a license, but the author is okay with redistribution.

import QtQml.Models
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common

/**
 * A service that provides easy access to the active Mpris player.
 */
Singleton {
	id: root;
	property list<MprisPlayer> players: Mpris.players.values.filter(player => isAcceptedPlayer(player));
	property MprisPlayer trackedPlayer: null;
	// 只在 trackedPlayer 仍被接受时才回退到它；否则一个已被过滤掉的
	// 浏览器 bus 会继续驱动栏与侧栏的媒体显示。
	property MprisPlayer activePlayer: {
		if (trackedPlayer && isAcceptedPlayer(trackedPlayer))
			return trackedPlayer;
		for (const p of players)
			return p;
		return null;
	}
	signal trackChanged(reverse: bool);

	property bool __reverse: false;

	property var activeTrack;

	readonly property bool hasActivePlasmaIntegration: Mpris.players.values.some(
		p => p.dbusName?.startsWith('org.mpris.MediaPlayer2.plasma-browser-integration')
	)
	// 浏览器 MPRIS bus 的名字 / 身份特征。
	// plasma-browser-integration 是 Chrome / Firefox 的浏览器扩展桥，
	// 它的 identity 就是 "Google Chrome"，一并归入浏览器。
	readonly property var browserNamePatterns: [
		"chrome", "chromium", "firefox", "brave", "edge", "opera", "vivaldi",
		"plasma-browser-integration"
	]

	// 用词边界而不是裸 includes："edge" 会命中 "knowledge" 这类词，
	// 把真正的音乐播放器静默过滤掉——那种失败没有任何提示，极难排查。
	// 正则只构造一次，避免每次判定都重新编译。
	readonly property var browserPatternRegex: {
		const escaped = browserNamePatterns.map(p =>
			p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
		return new RegExp("\\b(" + escaped.join("|") + ")\\b", "i");
	}

	function isBrowserPlayer(player) {
		if (!player)
			return false;
		// 只看 identity 和 desktopEntry，不能看 dbusName：
		// 所有 Electron 应用的 bus 名都是
		// org.mpris.MediaPlayer2.chromium.instanceN（MoeKoeMusic、Vesktop、
		// Element 等），拿 bus 名判定会把它们全当成浏览器过滤掉。
		const haystack = [
			player.desktopEntry ?? "",
			player.identity ?? ""
		].join(" ");
		return browserPatternRegex.test(haystack);
	}

	// 最终准入判定：先做去重，再按配置剔除浏览器。
	function isAcceptedPlayer(player) {
		if (!player)
			return false;
		if (!isRealPlayer(player))
			return false;
		if (Config.options.media.ignoreBrowserPlayers && isBrowserPlayer(player))
			return false;
		return true;
	}

	function isRealPlayer(player) {
        if (!Config.options.media.filterDuplicatePlayers) {
            return true;
        }
        // 浏览器原生 bus 的去重必须用 isBrowserPlayer 判定，
        // 不能裸看 dbusName 前缀：所有 Electron 应用的 bus 名都是
        // org.mpris.MediaPlayer2.chromium.instanceN，按前缀判断会把
        // MoeKoeMusic / Vesktop 这类真正的播放器一起干掉。
        return (
            !(hasActivePlasmaIntegration && isBrowserPlayer(player)) &&
            // playerctld just copies other buses and we don't need duplicates
            !player.dbusName?.startsWith('org.mpris.MediaPlayer2.playerctld') &&
            // Non-instance mpd bus
            !(player.dbusName?.endsWith('.mpd') && !player.dbusName.endsWith('MediaPlayer2.mpd')));
    }

	// Collapse duplicate MPRIS entries (same track exposed by two buses).
	// Lives on the singleton so any binding can call it — a copy local to
	// MediaControls.qml left SidebarRightContent.qml throwing "not defined".
	function filterDuplicatePlayers(players) {
		let filtered = [];
		let used = new Set();

		for (let i = 0; i < players.length; ++i) {
			if (used.has(i))
				continue;
			let p1 = players[i];
			let group = [i];

			// Find duplicates by trackTitle prefix
			for (let j = i + 1; j < players.length; ++j) {
				let p2 = players[j];
				if (p1.trackTitle && p2.trackTitle && (p1.trackTitle.includes(p2.trackTitle) || p2.trackTitle.includes(p1.trackTitle)) || (p1.position - p2.position <= 2 && p1.length - p2.length <= 2)) {
					group.push(j);
				}
			}

			// Pick the one with non-empty trackArtUrl, or fallback to the first
			let chosenIdx = group.find(idx => players[idx].trackArtUrl && players[idx].trackArtUrl.length > 0);
			if (chosenIdx === undefined)
				chosenIdx = group[0];

			filtered.push(players[chosenIdx]);
			group.forEach(idx => used.add(idx));
		}
		return filtered;
	}

	// Original stuff from fox below
	Instantiator {
		model: Mpris.players;

		Connections {
			required property MprisPlayer modelData;
			target: modelData;

			Component.onCompleted: {
				if (root.trackedPlayer == null || modelData.isPlaying) {
					root.trackedPlayer = modelData;
				}
			}

			Component.onDestruction: {
				if (root.trackedPlayer == null || !root.trackedPlayer.isPlaying) {
					for (const player of Mpris.players.values) {
						if (player.playbackState.isPlaying) {
							root.trackedPlayer = player;
							break;
						}
					}

					if (trackedPlayer == null && Mpris.players.values.length != 0) {
						trackedPlayer = Mpris.players.values[0];
					}
				}
			}

			function onPlaybackStateChanged() {
				if (root.trackedPlayer !== modelData) root.trackedPlayer = modelData;
			}
		}
	}

	Connections {
		target: activePlayer

		function onPostTrackChanged() {
			root.updateTrack();
		}

		function onTrackArtUrlChanged() {
			// console.log("arturl:", activePlayer.trackArtUrl)
			// root.updateTrack();
			if (root.activePlayer.uniqueId == root.activeTrack.uniqueId && root.activePlayer.trackArtUrl != root.activeTrack.artUrl) {
				// cantata likes to send cover updates *BEFORE* updating the track info.
				// as such, art url changes shouldn't be able to break the reverse animation
				const r = root.__reverse;
				root.updateTrack();
				root.__reverse = r;

			}
		}
	}

	onActivePlayerChanged: this.updateTrack();

	function updateTrack() {
		//console.log(`update: ${this.activePlayer?.trackTitle ?? ""} : ${this.activePlayer?.trackArtists}`)
		this.activeTrack = {
			uniqueId: this.activePlayer?.uniqueId ?? 0,
			artUrl: this.activePlayer?.trackArtUrl ?? "",
			title: this.activePlayer?.trackTitle || Translation.tr("Unknown Title"),
			artist: this.activePlayer?.trackArtist || Translation.tr("Unknown Artist"),
			album: this.activePlayer?.trackAlbum || Translation.tr("Unknown Album"),
		};

		this.trackChanged(__reverse);
		this.__reverse = false;
	}

	property bool isPlaying: this.activePlayer && this.activePlayer.isPlaying;
	property bool canTogglePlaying: this.activePlayer?.canTogglePlaying ?? false;
	function togglePlaying() {
		if (this.canTogglePlaying) this.activePlayer.togglePlaying();
	}

	property bool canGoPrevious: this.activePlayer?.canGoPrevious ?? false;
	function previous() {
		if (this.canGoPrevious) {
			this.__reverse = true;
			this.activePlayer.previous();
		}
	}

	property bool canGoNext: this.activePlayer?.canGoNext ?? false;
	function next() {
		if (this.canGoNext) {
			this.__reverse = false;
			this.activePlayer.next();
		}
	}

	property bool canChangeVolume: this.activePlayer && this.activePlayer.volumeSupported && this.activePlayer.canControl;

	property bool loopSupported: this.activePlayer && this.activePlayer.loopSupported && this.activePlayer.canControl;
	property var loopState: this.activePlayer?.loopState ?? MprisLoopState.None;
	function setLoopState(loopState: var) {
		if (this.loopSupported) {
			this.activePlayer.loopState = loopState;
		}
	}

	property bool shuffleSupported: this.activePlayer && this.activePlayer.shuffleSupported && this.activePlayer.canControl;
	property bool hasShuffle: this.activePlayer?.shuffle ?? false;
	function setShuffle(shuffle: bool) {
		if (this.shuffleSupported) {
			this.activePlayer.shuffle = shuffle;
		}
	}

	function setActivePlayer(player: MprisPlayer) {
		const targetPlayer = player ?? Mpris.players[0];
		console.log(`[Mpris] Active player ${targetPlayer} << ${activePlayer}`)

		if (targetPlayer && this.activePlayer) {
			this.__reverse = Mpris.players.indexOf(targetPlayer) < Mpris.players.indexOf(this.activePlayer);
		} else {
			// always animate forward if going to null
			this.__reverse = false;
		}

		this.trackedPlayer = targetPlayer;
	}

	IpcHandler {
		target: "mpris"

		function pauseAll(): void {
			for (const player of Mpris.players.values) {
				if (player.canPause) player.pause();
			}
		}

		function playPause(): void { root.togglePlaying(); }
		function previous(): void { root.previous(); }
		function next(): void { root.next(); }
	}
}
