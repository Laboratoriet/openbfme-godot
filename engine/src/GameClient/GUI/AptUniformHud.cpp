// OpenBFME. GPL-3.0.
// See AptUniformHud.h (lane IOS-29: the round-HUD rule, OpenBFME presentation, not retail).

#include "GameClient/GUI/AptUniformHud.h"

#include "Libraries/Source/Apt/Apt.h"
#include "Libraries/Source/Apt/AptCharacterInst.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>

namespace
{
// the x and y scale a presentation matrix (a viewport or present transform: a scale and a move) applies
float scaleOfX(const AptMatrix &m) { return std::hypot(m.a, m.b); }
float scaleOfY(const AptMatrix &m) { return std::hypot(m.c, m.d); }

bool isIdentity(const AptMatrix &m)
{
	return m.a == 1.0f && m.b == 0.0f && m.c == 0.0f && m.d == 1.0f && m.tx == 0.0f && m.ty == 0.0f;
}

// a level is laid out child by child when its screen gave one of the root's children a viewport transform (AptPalantir::setViewportSize)
bool laidOutPerChild(const AptSpriteInst &root)
{
	for (const AptCharacterInst *c : root.children())
	{
		if (!isIdentity(c->viewportTransform))
		{
			return true;
		}
	}
	return false;
}

// a clip that carries a button (a control the player presses): never a backdrop
bool hasButton(AptCharacterInst *c)
{
	if (c->asButton())
	{
		return true;
	}
	if (AptSpriteInst *s = c->asSprite())
	{
		for (AptCharacterInst *k : s->children())
		{
			if (hasButton(k))
			{
				return true;
			}
		}
	}
	return false;
}

// the anchor of a box [lo, hi] on a stage axis of `extent`: the box's point at its own relative place (flush left: its left edge; flush right: its
// right edge; centred: its centre)
float anchorOf(float lo, float hi, float extent)
{
	const float size = hi - lo;
	if (extent - size <= 1e-3f)
	{
		return (lo + hi) * 0.5f; // as large as the stage or larger: its centre
	}
	const float t = std::clamp(lo / (extent - size), 0.0f, 1.0f);
	return lo + t * size;
}
} // namespace

float AptUniformHud::matrixAspect(const AptMatrix &m)
{
	const float sx = scaleOfX(m), sy = scaleOfY(m);
	// a turned clip (its x axis not along the stage's) has no single x / y ratio on the screen
	const bool turned = std::fabs(m.b) > 1e-4f * sx || std::fabs(m.c) > 1e-4f * sy;
	return sx > 0.0f && sy > 0.0f && !turned ? sx / sy : 0.0f;
}

float AptUniformHud::widescreenBuild(const AptSpriteInst &root)
{
	std::vector<float> ratios;
	for (const AptCharacterInst *c : root.children())
	{
		const float r = matrixAspect(c->matrix);
		if (r > 0.0f)
		{
			ratios.push_back(r);
		}
	}
	if (ratios.empty())
	{
		return 1.0f;
	}
	std::nth_element(ratios.begin(), ratios.begin() + ratios.size() / 2, ratios.end());
	const float median = ratios[ratios.size() / 2];
	return ratioOff(median, 1.0f) <= kTolerance ? 1.0f : median;
}

float AptUniformHud::builtStretch(float build, const AptCharacterInst &child)
{
	if (build == 1.0f)
	{
		return 1.0f;
	}
	const float own = matrixAspect(child.matrix);
	return own <= 0.0f || ratioOff(own, 1.0f) <= kTolerance ? 1.0f : build; // uniform (or turned): not squeezed by the build
}

bool AptUniformHud::Menus::has(int level) const
{
	return std::find(levels.begin(), levels.end(), level) != levels.end();
}

void AptUniformHud::safeCentre(const AptStageMapping &mapping, const float safeInsets[4], float &cx, float &cy)
{
	const float wx = safeInsets[0] + (mapping.windowW - safeInsets[0] - safeInsets[2]) * 0.5f;
	const float wy = safeInsets[1] + (mapping.windowH - safeInsets[1] - safeInsets[3]) * 0.5f;
	mapping.windowToStage(wx, wy, cx, cy);
}

AptMatrix AptUniformHud::correction(const AptCharacterInst &unit, const AptMatrix &parentChain, const AptStageMapping &mapping, float &fixX, float &fixY,
	const float *centre, float built)
{
	fixX = fixY = 1.0f;
	// the presentation scale above the unit: the mapping, the parents' viewport / present transforms (parentChain's scale: the authored matrices of
	// a level's root and its children are 1 in the HUD movies; INFERENCE: a rotated or scaled authored parent would count here as well)
	// lane IOS-39: and the stretch a widescreen build of the movie bakes into the unit's own matrix (builtStretch; 1 for RotWK's)
	const float ex = mapping.scaleX() * scaleOfX(parentChain) * scaleOfX(unit.viewportTransform) * built;
	const float ey = mapping.scaleY() * scaleOfY(parentChain) * scaleOfY(unit.viewportTransform);
	if (!(ex > 0.0f) || !(ey > 0.0f) || ratioOff(ex, ey) <= kTolerance)
	{
		return AptMatrix();
	}
	const float s = std::min(ex, ey);
	fixX = s / ex;
	fixY = s / ey;
	// the unit's content box on the stage (without a correction of its own)
	const AptMatrix placed = parentChain.concat(unit.viewportTransform.concat(unit.matrix));
	float x0, y0, x1, y1;
	float bx0, by0, bx1, by1;
	if (unit.contentBounds(x0, y0, x1, y1))
	{
		bx0 = by0 = 1e30f;
		bx1 = by1 = -1e30f;
		const float xs[4] = { x0, x1, x0, x1 }, ys[4] = { y0, y0, y1, y1 };
		for (int i = 0; i < 4; ++i)
		{
			float px, py;
			placed.apply(xs[i], ys[i], px, py);
			bx0 = std::min(bx0, px);
			by0 = std::min(by0, py);
			bx1 = std::max(bx1, px);
			by1 = std::max(by1, py);
		}
	}
	else
	{
		placed.apply(0.0f, 0.0f, bx0, by0); // nothing drawn yet: its origin
		bx1 = bx0;
		by1 = by0;
	}
	const float ax = anchorOf(bx0, bx1, mapping.stageW), ay = anchorOf(by0, by1, mapping.stageH);
	AptMatrix fix; // on the stage: x' = ax + fixX (x - ax)
	fix.a = fixX;
	fix.d = fixY;
	fix.tx = ax * (1.0f - fixX);
	fix.ty = ay * (1.0f - fixY);
	if (centre)
	{
		// lane IOS-32, a menu: on the shrunk axis the stage's centre goes to the safe area's centre (x' = c + fix (x - stage / 2)); the other axis
		// (factor 1) keeps the stage's stretch edge to edge
		if (fixX < 1.0f)
		{
			fix.tx = centre[0] - fixX * mapping.stageW * 0.5f;
		}
		if (fixY < 1.0f)
		{
			fix.ty = centre[1] - fixY * mapping.stageH * 0.5f;
		}
	}
	if (isIdentity(parentChain))
	{
		return fix;
	}
	// presentTransform sits under the parent: parent * present = fix * parent
	bool ok = false;
	const AptMatrix inv = parentChain.inverse(&ok);
	if (!ok)
	{
		fixX = fixY = 1.0f;
		return AptMatrix();
	}
	return inv.concat(fix.concat(parentChain));
}

void AptUniformHud::apply(Apt &apt, const AptStageMapping &mapping, bool enabled)
{
	apply(apt, mapping, enabled, Menus());
}

void AptUniformHud::apply(Apt &apt, const AptStageMapping &mapping, bool enabled, const Menus &menus)
{
	float centre[2];
	safeCentre(mapping, menus.safeInsets, centre[0], centre[1]);
	for (int level : apt.loadedLevels())
	{
		AptSpriteInst *root = apt.level(level);
		if (!root)
		{
			continue;
		}
		const bool perChild = laidOutPerChild(*root);
		float fx, fy;
		if (!enabled || perChild)
		{
			root->presentTransform = AptMatrix();
		}
		else
		{
			root->presentTransform = correction(*root, AptMatrix(), mapping, fx, fy, menus.has(level) ? centre : nullptr);
		}
		const AptMatrix rootChain = root->globalMatrix();
		const float build = perChild ? widescreenBuild(*root) : 1.0f; // lane IOS-39
		const bool rootFixed = enabled && !perChild && !isIdentity(root->presentTransform);
		for (AptCharacterInst *c : root->children())
		{
			c->presentTransform = enabled && perChild ? correction(*c, rootChain, mapping, fx, fy, nullptr, builtStretch(build, *c)) : AptMatrix();
			if (rootFixed)
			{
				c->presentTransform = backdrop(*root, *c, mapping);
			}
		}
	}
}

void AptUniformHud::audit(Apt &apt, const AptStageMapping &mapping, std::vector<Entry> &out)
{
	for (int level : apt.loadedLevels())
	{
		AptSpriteInst *root = apt.level(level);
		if (!root)
		{
			continue;
		}
		const bool perChild = laidOutPerChild(*root);
		// the walk: the presentation scale (the present and viewport transforms' x / y scales) down to each instance
		struct Walk
		{
			static void go(AptCharacterInst *inst, float px, float py, int depth, int level, bool perChild, const AptStageMapping &m, std::vector<Entry> &out,
				float build)
			{
				if (!inst || !inst->defined() || !inst->visible)
				{
					return;
				}
				const bool unit = perChild ? depth == 1 : depth == 0;
				// lane IOS-39: a laid-out root child counts with the stretch a widescreen build bakes into it (builtStretch; 1 for RotWK's movies), and its
				// content inherits it
				const float built = unit && perChild ? builtStretch(build, *inst) : 1.0f;
				const float kx = px * scaleOfX(inst->presentTransform) * scaleOfX(inst->viewportTransform) * built;
				const float ky = py * scaleOfY(inst->presentTransform) * scaleOfY(inst->viewportTransform);
				if (unit || !isIdentity(inst->viewportTransform) || !isIdentity(inst->presentTransform))
				{
					float x0, y0, x1, y1;
					// a unit or transformed clip with nothing to draw (an empty slot) squashes nothing
					if (inst->contentBounds(x0, y0, x1, y1))
					{
						Entry e;
						e.level = level;
						e.path = inst->targetPath();
						e.sx = m.scaleX() * kx;
						e.sy = m.scaleY() * ky;
						e.fixX = scaleOfX(inst->presentTransform);
						e.fixY = scaleOfY(inst->presentTransform);
						e.unit = unit;
						// its box in window pixels, edge to edge on the more stretched axis?
						const AptMatrix g = inst->globalMatrix();
						float lo = 1e30f, hi = -1e30f;
						const bool alongX = e.sx > e.sy;
						const float xs[4] = { x0, x1, x0, x1 }, ys[4] = { y0, y0, y1, y1 };
						for (int i = 0; i < 4; ++i)
						{
							float gx, gy, wx, wy;
							g.apply(xs[i], ys[i], gx, gy);
							m.stageToWindow(gx, gy, wx, wy);
							lo = std::min(lo, alongX ? wx : wy);
							hi = std::max(hi, alongX ? wx : wy);
						}
						e.fullBleed = lo <= 1.0f && hi >= (alongX ? m.windowW : m.windowH) - 1.0f;
						out.push_back(e);
					}
				}
				if (AptSpriteInst *s = inst->asSprite())
				{
					for (AptCharacterInst *c : s->children())
					{
						go(c, kx, ky, depth + 1, level, perChild, m, out, build);
					}
				}
			}
		};
		Walk::go(root, 1.0f, 1.0f, 0, level, perChild, mapping, out, perChild ? widescreenBuild(*root) : 1.0f);
	}
}

namespace
{
// the level root and the root's child at the start of `path` ("_level<n>.<child>..."); child null when the path is the root's or names no child
const AptSpriteInst *rootAndChild(Apt &apt, const std::string &path, const AptCharacterInst *&child)
{
	child = nullptr;
	static const char kPrefix[] = "_level";
	if (path.compare(0, sizeof(kPrefix) - 1, kPrefix) != 0)
	{
		return nullptr;
	}
	const std::size_t dot = path.find('.');
	const int level = std::atoi(path.substr(sizeof(kPrefix) - 1, dot == std::string::npos ? std::string::npos : dot - (sizeof(kPrefix) - 1)).c_str());
	const AptSpriteInst *root = apt.level(level);
	if (!root || dot == std::string::npos)
	{
		return root;
	}
	const std::size_t end = path.find('.', dot + 1);
	const std::string segment = path.substr(dot + 1, end == std::string::npos ? std::string::npos : end - dot - 1);
	for (const AptCharacterInst *c : root->children())
	{
		if (c->pathSegment() == segment)
		{
			child = c;
			break;
		}
	}
	return root;
}
} // namespace

void AptUniformHud::presentScale(Apt &apt, const std::string &path, float &fx, float &fy)
{
	fx = fy = 1.0f;
	const AptCharacterInst *child = nullptr;
	const AptSpriteInst *root = rootAndChild(apt, path, child);
	if (!root)
	{
		return;
	}
	fx = scaleOfX(root->presentTransform);
	fy = scaleOfY(root->presentTransform);
	if (child)
	{
		fx *= scaleOfX(child->presentTransform);
		fy *= scaleOfY(child->presentTransform);
	}
}

bool AptUniformHud::isBackdrop(Apt &apt, const std::string &path)
{
	// apply() gives a corrected root's child a presentTransform only when backdrop() found it one; laid out per child, the root has none
	const AptCharacterInst *child = nullptr;
	const AptSpriteInst *root = rootAndChild(apt, path, child);
	return root && child && !isIdentity(root->presentTransform) && !isIdentity(child->presentTransform);
}

AptMatrix AptUniformHud::backdrop(AptSpriteInst &root, AptCharacterInst &child, const AptStageMapping &mapping)
{
	// the axis the root's correction shrinks, and the child's box on the stage without it
	const AptMatrix &fix = root.presentTransform;
	const bool alongX = fix.a < fix.d;
	const AptMatrix placed = root.viewportTransform.concat(root.matrix).concat(child.viewportTransform.concat(child.matrix));
	float x0, y0, x1, y1;
	if (!child.contentBounds(x0, y0, x1, y1) || hasButton(&child))
	{
		return AptMatrix();
	}
	float lo = 1e30f, hi = -1e30f;
	const float xs[4] = { x0, x1, x0, x1 }, ys[4] = { y0, y0, y1, y1 };
	for (int i = 0; i < 4; ++i)
	{
		float px, py;
		placed.apply(xs[i], ys[i], px, py);
		lo = std::min(lo, alongX ? px : py);
		hi = std::max(hi, alongX ? px : py);
	}
	const float extent = alongX ? mapping.stageW : mapping.stageH;
	if (lo > 1.0f || hi < extent - 1.0f)
	{
		return AptMatrix();
	}
	// edge to edge, no control in it: a backdrop (a shade, a band). It keeps the root's correction on its other axis only (its place), and the
	// stage's stretch on this one: child.present = R^-1 * fix^-1 * keep * R, R the root's own transform
	AptMatrix keep = fix;
	if (alongX)
	{
		keep.a = 1.0f;
		keep.tx = 0.0f;
	}
	else
	{
		keep.d = 1.0f;
		keep.ty = 0.0f;
	}
	const AptMatrix r = root.viewportTransform.concat(root.matrix);
	bool okR = false, okF = false;
	const AptMatrix rInv = r.inverse(&okR), fixInv = fix.inverse(&okF);
	if (!okR || !okF)
	{
		return AptMatrix();
	}
	return rInv.concat(fixInv).concat(keep).concat(r);
}
