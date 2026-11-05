// OpenBFME. GPL-3.0.
//
// Lane HUD-6: the side command bar's update (InGameSideCommandBar.apt, the builder's build list in its carved frame). See AptPalantir.h.
//
// TARGET FACTS (RotWK game.dat, caveat S-001; AptInGameSideCommandBar::Impl, BFME2 decomp AptInGameSideCommandBar.cpp is the donor for the class layout,
// tier B same-shape for RW 0x92F082):
//   * the update RW 0x92F27D: nothing before the movie loaded (+ 0x14 == 0); the context object (+ 0x1C) must exist, have the template KindOf DOZER
//     (+ 0x109 bit 0x40), be controlled by the local player (RW 0x68B678 == RW 0x6A8839) whose + 0x770 is 0, and UpdateButtonVisiblity must show at least one
//     button; then FadeIn when the bar is neither fading in nor shown (RW 0x92EDDC, states 2 / 3), else FadeOut when it is (RW 0x92EE1C). The content updaters
//     run only while the bar fades in or is shown (states 2 / 3, RW 0x92F316): a bar that fades out keeps what it showed;
//   * UpdateButtonVisiblity RW 0x92F082: the control bar's 33 windows in order (TheControlBar + 0xDC), each visible one whose CommandButton is Radial (+ 0x101)
//     takes the next frame (at most 15, stopping at the first frame the movie did not report); a frame that showed another window is hidden first
//     (RW 0x92F015 from it on); a new frame gets SetButtonState(<index>, "_show") on the movie (RW 0x92BDC5 with the "%d" of the index, strings RW 0xC7EF50 /
//     0xC19534) and its updater; afterwards every frame from the count on is hidden;
//   * HideButtons RW 0x92F015: from the last shown frame down to `from`: SetButtonState(<index>, "_hide") (RW 0xC1952C), its updater released, its window -1.
// The movie's SetButtonState shows the frame piece of that button (SideCommandBar01 .. 12.tga with the gold curls, UpdateFrameState / UpdateNeighborFrameStates
// pick _top / _middle / _bottom / _topbottom from the neighbours): without these calls the frame stays hidden and only the bare icons show.
// INFERENCE (S-2700): the local player's + 0x770 (unidentified) is taken as 0; the content of a frame whose window changed is updated in place (syncFrames) where
// retail releases the frame's updater and makes a new one.

#include "GameClient/GUI/AptScreens/AptPalantir.h"
#include "Libraries/Source/Apt/Apt.h"
#include "Libraries/Source/Apt/AptCharacterInst.h"

#include <algorithm>

void AptPalantir::sideBarLoaded(const std::string &arg)
{
	// RW 0x92EE5C: the argument (the movie's clip) is kept and the bar is loaded (state 1); RW 0x92ED9C (unloaded) forgets the frames
	m_sidePrefix = arg;
	if (m_sidePrefix.rfind("_level", 0) == 0) // the clip path without its "_level<N>." prefix (RW 0x815563, as the frames' names)
	{
		const size_t dot = m_sidePrefix.find('.');
		m_sidePrefix = dot == std::string::npos ? std::string() : m_sidePrefix.substr(dot + 1);
	}
	m_sideCount = 0;
	for (int &k : m_sideKey)
	{
		k = -1;
	}
}

void AptPalantir::hideSideButtons(int from)
{
	while (from < m_sideCount)
	{
		--m_sideCount;
		call(m_sidePrefix, "SetButtonState", { std::to_string(m_sideCount), "_hide" });
		if (m_sideBarCalls.size() >= 64)
		{
			m_sideBarCalls.erase(m_sideBarCalls.begin());
		}
		m_sideBarCalls.push_back(std::to_string(m_sideCount) + " _hide");
		m_sideKey[m_sideCount] = -1;
	}
}

bool AptPalantir::updateSideButtonVisibility(const std::vector<ControlBarButton> &buttons)
{
	int slotNum = 0;
	for (const ControlBarButton &b : buttons) // ControlBar::sideButtons: the visible Radial buttons in window order
	{
		if (slotNum > 14 || m_sideFramePath[slotNum].empty())
		{
			break; // RW 0x92F0A1 (15 frames) / RW 0x92F0E3 (a frame the movie has not reported)
		}
		if (slotNum < m_sideCount && m_sideKey[slotNum] != b.slot)
		{
			hideSideButtons(slotNum);
		}
		if (slotNum >= m_sideCount)
		{
			call(m_sidePrefix, "SetButtonState", { std::to_string(slotNum), "_show" });
			if (m_sideBarCalls.size() >= 64)
			{
				m_sideBarCalls.erase(m_sideBarCalls.begin());
			}
			m_sideBarCalls.push_back(std::to_string(slotNum) + " _show");
			m_sideKey[slotNum] = b.slot;
			m_sideCount = slotNum + 1;
		}
		++slotNum;
	}
	hideSideButtons(slotNum);
	return slotNum > 0;
}

void AptPalantir::syncSideBar(const ControlBar &bar)
{
	if (!m_sideBarLoaded)
	{
		return; // RW 0x92F283: + 0x14 == 0
	}
	const bool shown = m_sideBarGate && updateSideButtonVisibility(bar.sideButtons());
	if (shown != m_sideShown)
	{
		m_sideShown = shown;
		call(m_sidePrefix, shown ? "FadeIn" : "FadeOut", {});
	}
	if (m_sideShown)
	{
		syncFrames(bar.sideButtons(), false); // the updaters (RW 0x92F316): only while the bar fades in or is shown
	}
}

bool AptPalantir::contentSlotAt(const std::string &path, bool &arc, int &slot) const
{
	// lane HUD-6 (INFERENCE, S-2703): a clip inside "<level>.<frame>.content" belongs to the button that frame shows (syncFrames' keys)
	for (int pass = 0; pass < 2; ++pass)
	{
		const bool inArc = pass == 0;
		const int n = inArc ? kArcPositions : kSidePositions;
		for (int i = 0; i < n; ++i)
		{
			const std::string &frame = inArc ? m_arcFramePath[i] : m_sideFramePath[i];
			const Slot &s = inArc ? m_arc[i] : m_side[i];
			if (frame.empty() || !s.created || s.slot < 0)
			{
				continue;
			}
			const std::string key = levelPrefix() + frame + (m_bfme1 && inArc ? "" : ".content");
			if (path == key || (path.size() > key.size() && path.compare(0, key.size(), key) == 0 && path[key.size()] == '.'))
			{
				arc = inArc;
				slot = s.slot;
				return true;
			}
		}
	}
	return false;
}

// ---- lane IOS-27 (OpenBFME presentation, not retail): the side bar as a block of one or two columns (AptPalantir.h) --------------------------------------
// InGameSideCommandBar.apt (read from the movie, measured: hud2 palantir tests): SideCommandBar.ButtonSet holds the twelve frames Button0 .. Button11 in one
// column (46 units apart, the reported button frames are their "Button" children), each with its frame art "Frame" (labels _middle, _top, _topbottom,
// _bottom: the gold ends a column shows above its first and below its last button) and ButtonGlass; flashEffects.Button<N> is frame N's flash, placed by
// the movie at the frame's centre. The movie's FadeIn / FadeOut slide ButtonSet in from / out past the stage's right edge (its x) by a little more than a
// column's width. The layout moves whole frames (a viewport transform on ButtonN and its flash: the hit test, the tap assist and the help read the global
// matrix, so they follow), sets the frame art of the frames that end a column, and stretches ButtonSet's slide by the block's width in columns.

namespace
{
const char *const kFrameLabels[4] = { "_middle", "_top", "_topbottom", "_bottom" };

// the label of the section of `s`'s timeline it stands in ("" none of kFrameLabels)
std::string frameSection(const AptSpriteInst &s)
{
	std::string best;
	int bestFrame = -1;
	for (const char *l : kFrameLabels)
	{
		const int f = s.labelFrame(l);
		if (f >= 0 && f <= s.frame && f > bestFrame)
		{
			best = l;
			bestFrame = f;
		}
	}
	return best;
}

// the parent path of a dotted clip path ("" for a top-level name)
std::string parentPath(const std::string &path)
{
	const size_t dot = path.rfind('.');
	return dot == std::string::npos ? std::string() : path.substr(0, dot);
}
} // namespace

void AptPalantir::resetSideBarArrangement(AptSpriteInst *root)
{
	if (!m_sideArranged)
	{
		return;
	}
	m_sideArranged = false;
	m_sideColumns = 1;
	for (int i = 0; i < 16; ++i)
	{
		if (m_sideFramePath[i].empty())
		{
			continue;
		}
		const std::string frame = parentPath(m_sideFramePath[i]);
		AptCharacterInst *c = windows().apt().resolvePath(root, frame);
		if (!c)
		{
			continue;
		}
		c->viewportTransform = AptMatrix();
		if (AptSpriteInst *set = dynamic_cast<AptSpriteInst *>(c->parent()))
		{
			set->viewportTransform = AptMatrix();
			if (AptCharacterInst *flash = windows().apt().resolvePath(set, "flashEffects." + c->instName()))
			{
				flash->viewportTransform = AptMatrix();
			}
		}
		if (!m_sideForcedState[i].empty())
		{
			// back to the movie's own choice for one column (UpdateNeighborFrameStates: the neighbours' indices)
			const char *label = m_sideCount == 1 ? "_topbottom" : (i == 0 ? "_top" : (i == m_sideCount - 1 ? "_bottom" : "_middle"));
			if (i < m_sideCount)
			{
				call(frame + ".Frame", "gotoAndPlay", { label });
			}
			m_sideForcedState[i].clear();
		}
	}
}

bool AptPalantir::arrangeSideBar(AptSpriteInst *root, bool portrait, float vscale, float stageWidth, float stageHeight, float safeTop, float safeBottom, float &k)
{
	const float target = k;
	const int n = std::min(m_sideCount, 16);
	if (target <= 1.0f || n < 1 || m_bfme1)
	{
		resetSideBarArrangement(root);
		return false;
	}
	// the shown frames (ButtonN, the reported frame's parent) and their column's clip
	AptSpriteInst *frames[16] = {};
	for (int i = 0; i < n; ++i)
	{
		AptCharacterInst *c = m_sideFramePath[i].empty() ? nullptr : windows().apt().resolvePath(root, parentPath(m_sideFramePath[i]));
		frames[i] = c ? c->asSprite() : nullptr;
		if (!frames[i] || (i > 0 && frames[i]->parent() != frames[0]->parent()))
		{
			if (m_callErrors.size() < 200)
			{
				m_callErrors.push_back("IOS-27 side bar layout: frame " + std::to_string(i) + " (" + m_sideFramePath[i] + ") is not a clip of the bar's column");
			}
			resetSideBarArrangement(root);
			return false;
		}
	}
	AptSpriteInst *set = dynamic_cast<AptSpriteInst *>(frames[0]->parent());
	AptCharacterInst *bar = set ? set->parent() : nullptr;
	if (!set || !bar || bar->parent() != root)
	{
		if (m_callErrors.size() < 200)
		{
			m_callErrors.push_back("IOS-27 side bar layout: the frames' column is not a clip of a child of the Palantir's root");
		}
		resetSideBarArrangement(root);
		return false;
	}
	// the column's measures (the movie's own, unscaled): its pitch, a frame's width (the frames are square), what the frame art reaches above the first
	// button's origin (its _top end) and below the last's (its _bottom end)
	const float x0 = frames[0]->matrix.tx, y0 = frames[0]->matrix.ty;
	const float pitch = n > 1 ? frames[1]->matrix.ty - y0 : 0.0f; // one button is one column: no pitch needed
	float bx0, by0, bx1, by1, lx0, ly0, lx1, ly1;
	if ((n > 1 && pitch <= 0.0f) || !frames[0]->contentBounds(bx0, by0, bx1, by1) || !frames[n - 1]->contentBounds(lx0, ly0, lx1, ly1))
	{
		if (m_callErrors.size() < 200)
		{
			m_callErrors.push_back("IOS-27 side bar layout: the column's frames have no pitch or no frame art to measure");
		}
		resetSideBarArrangement(root);
		return false;
	}
	const float capAbove = std::max(0.0f, -by0), capBelow = std::max(0.0f, ly1);
	const float width = pitch;
	const float safeHeight = safeBottom - safeTop;
	auto blockHeight = [&](int rows) { return (float)(rows - 1) * pitch + capAbove + capBelow; };
	int columns = !portrait && n > 1 && (n > kSideBarMaxRows || vscale * target * blockHeight(n) > safeHeight) ? 2 : 1;
	if (m_protoSideColumns == 1)
	{
		columns = 1; // lane IOS-38 (prototype): one column standing in the bottom-right corner
	}
	const int rows = (n + columns - 1) / columns;
	k = target;
	if (vscale * k * blockHeight(rows) > safeHeight)
	{
		k = std::max(1.0f, safeHeight / (vscale * blockHeight(rows)));
	}
	m_sideColumns = columns;
	m_sideArranged = true;
	// landscape: the block stands in the bar's bottom-right corner (the group's anchor, the safe area's corner): its last row's frame art ends at the
	// stage's bottom. Portrait: the column's first frame art starts at `safeTop` once the group's transform (k about the stage's bottom-right corner,
	// which goes to the safe area's) has placed it. Root space of the column's y: the bar's and ButtonSet's matrices (their x is the slide)
	const float setY = bar->matrix.ty + bar->matrix.d * set->matrix.ty;
	const float unitY = bar->matrix.d * set->matrix.d;
	const float topRoot = stageHeight + (safeTop - safeBottom) / (vscale * k);
	const float bottomOrigin = portrait ? topRoot + capAbove + (float)(rows - 1) * pitch : stageHeight - capBelow;
	const int firstRows = rows, secondRows = n - rows;
	for (int i = 0; i < 16; ++i)
	{
		AptCharacterInst *c = i < n ? frames[i] : nullptr;
		if (!c && !m_sideFramePath[i].empty())
		{
			c = windows().apt().resolvePath(root, parentPath(m_sideFramePath[i]));
		}
		if (!c)
		{
			continue;
		}
		AptMatrix move;
		std::string label;
		if (i < n)
		{
			// column-major, the columns' last buttons on the bottom row: the second (shorter) column starts a row lower
			const int column = columns == 2 && i >= firstRows ? 1 : 0;
			const int inColumn = column == 0 ? i : i - firstRows;
			const int count = column == 0 ? firstRows : secondRows;
			const int row = inColumn + (rows - count);
			const float wantY = bottomOrigin - (float)(rows - 1 - row) * pitch;
			move.tx = columns == 2 && column == 0 ? -width : 0.0f;
			move.ty = (wantY - setY) / unitY - c->matrix.ty;
			label = count == 1 ? "_topbottom" : (inColumn == 0 ? "_top" : (inColumn == count - 1 ? "_bottom" : "_middle"));
		}
		c->viewportTransform = move;
		if (AptCharacterInst *flash = windows().apt().resolvePath(set, "flashEffects." + c->instName()))
		{
			flash->viewportTransform = move;
		}
		AptSpriteInst *art = i < n ? dynamic_cast<AptSpriteInst *>(windows().apt().resolvePath(c, "Frame")) : nullptr;
		if (art && !label.empty() && frameSection(*art) != label)
		{
			call(parentPath(m_sideFramePath[i]) + ".Frame", "gotoAndPlay", { label });
			m_sideForcedState[i] = label;
		}
	}
	// FadeOut slides ButtonSet right by a little more than one column: two columns slide twice as far, so the bar still leaves the screen. The shown
	// position puts the column's right edge on the stage's
	const float shownX = (stageWidth - bar->matrix.tx) / bar->matrix.a - x0 * set->matrix.a;
	set->viewportTransform = AptMatrix();
	set->viewportTransform.tx = (float)(columns - 1) * (set->matrix.tx - shownX);
	return true;
}
