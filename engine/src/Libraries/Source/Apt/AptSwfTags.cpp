// OpenBFME. GPL-3.0.
// See AptSwfTags.h.

#include "Libraries/Source/Apt/AptSwfTags.h"

namespace aptswf
{

namespace
{

// A DefineShape3 as drawing: layers of styles, each with paths (start point, selections, absolute edge points).
struct ShapeStyle
{
	std::uint8_t type = 0;
	std::vector<std::uint8_t> raw; // colour / gradient bytes (exact)
	std::uint16_t bitmapId = 0;
	SwfMatrix matrix;              // bitmap fills
	bool operator==(const ShapeStyle &o) const = delete;
};

struct ShapePath
{
	std::int32_t x = 0, y = 0;
	std::uint32_t fill0 = 0, fill1 = 0, line = 0;
	std::vector<std::int32_t> points; // edge records as absolute coordinates (2 per straight edge, 4 per curve) with a kind marker
};

struct ShapeLayer
{
	std::vector<ShapeStyle> fills;
	std::vector<std::vector<std::uint8_t>> lines; // LINESTYLE bytes
	std::vector<ShapePath> paths;
};

struct ShapeDrawing
{
	std::uint16_t id = 0;
	std::int32_t bounds[4] = { 0, 0, 0, 0 };
	std::vector<ShapeLayer> layers;
};

bool readFillStyles(SwfReader &r, std::vector<ShapeStyle> &out)
{
	std::uint32_t n = r.u8();
	if (n == 0xFF)
	{
		n = r.u16();
	}
	for (std::uint32_t i = 0; i < n && r.ok(); ++i)
	{
		ShapeStyle s;
		s.type = r.u8();
		if (s.type == 0x00)
		{
			s.raw = r.bytes(4);
		}
		else if (s.type >= 0x40 && s.type <= 0x43)
		{
			s.bitmapId = r.u16();
			s.matrix = r.matrix();
		}
		else
		{
			return false; // gradients: never written by the converter
		}
		out.push_back(s);
	}
	return r.ok();
}

bool readLineStyles(SwfReader &r, std::vector<std::vector<std::uint8_t>> &out)
{
	std::uint32_t n = r.u8();
	if (n == 0xFF)
	{
		n = r.u16();
	}
	for (std::uint32_t i = 0; i < n && r.ok(); ++i)
	{
		out.push_back(r.bytes(6)); // width u16 + RGBA (DefineShape3)
	}
	return r.ok();
}

bool decodeShape3(const std::vector<std::uint8_t> &body, ShapeDrawing &d)
{
	SwfReader r(body.data(), body.size());
	d.id = r.u16();
	r.rect(d.bounds);
	d.layers.emplace_back();
	if (!readFillStyles(r, d.layers.back().fills) || !readLineStyles(r, d.layers.back().lines))
	{
		return false;
	}
	int fillBits = (int)r.ub(4), lineBits = (int)r.ub(4);
	std::int32_t x = 0, y = 0;
	std::uint32_t f0 = 0, f1 = 0, ln = 0;
	ShapePath *path = nullptr;
	auto startPath = [&]() {
		d.layers.back().paths.emplace_back();
		path = &d.layers.back().paths.back();
		path->x = x;
		path->y = y;
		path->fill0 = f0;
		path->fill1 = f1;
		path->line = ln;
	};
	for (int guard = 0; guard < 10000000 && r.ok(); ++guard)
	{
		if (r.ub(1) == 0)
		{
			const std::uint32_t flags = r.ub(5);
			if (flags == 0)
			{
				break; // EndShapeRecord
			}
			if (flags & 0x01)
			{
				const int n = (int)r.ub(5);
				x = r.sb(n);
				y = r.sb(n);
			}
			if (flags & 0x02)
			{
				f0 = r.ub(fillBits);
			}
			if (flags & 0x04)
			{
				f1 = r.ub(fillBits);
			}
			if (flags & 0x08)
			{
				ln = r.ub(lineBits);
			}
			if (flags & 0x10)
			{
				d.layers.emplace_back();
				if (!readFillStyles(r, d.layers.back().fills) || !readLineStyles(r, d.layers.back().lines))
				{
					return false;
				}
				fillBits = (int)r.ub(4);
				lineBits = (int)r.ub(4);
				f0 = f1 = ln = 0; // a new layer starts with nothing selected
			}
			path = nullptr; // the next edge starts a new path with the state now in effect
		}
		else
		{
			if (!path)
			{
				startPath();
			}
			const bool straight = r.ub(1) != 0;
			const int n = (int)r.ub(4) + 2;
			if (straight)
			{
				std::int32_t dx = 0, dy = 0;
				if (r.ub(1))
				{
					dx = r.sb(n);
					dy = r.sb(n);
				}
				else if (r.ub(1))
				{
					dy = r.sb(n);
				}
				else
				{
					dx = r.sb(n);
				}
				x += dx;
				y += dy;
				path->points.insert(path->points.end(), { 0, x, y });
			}
			else
			{
				const std::int32_t cx = x + r.sb(n), cy = y + r.sb(n);
				x = cx + r.sb(n);
				y = cy + r.sb(n);
				path->points.insert(path->points.end(), { 1, cx, cy, x, y });
			}
		}
	}
	// paths without edges draw nothing
	for (ShapeLayer &l : d.layers)
	{
		std::vector<ShapePath> kept;
		for (ShapePath &p : l.paths)
		{
			if (p.points.empty())
			{
				continue;
			}
			// a path that continues the previous one from its end point with the same selection is the same path (an encoder
			// may or may not write the style record in between)
			if (!kept.empty())
			{
				ShapePath &prev = kept.back();
				const std::size_t n = prev.points.size();
				if (prev.fill0 == p.fill0 && prev.fill1 == p.fill1 && prev.line == p.line && prev.points[n - 2] == p.x && prev.points[n - 1] == p.y)
				{
					prev.points.insert(prev.points.end(), p.points.begin(), p.points.end());
					continue;
				}
			}
			kept.push_back(std::move(p));
		}
		l.paths = std::move(kept);
	}
	return r.ok();
}

bool nearFixed(std::int32_t a, std::int32_t b, std::int32_t tol)
{
	return a >= b - tol && a <= b + tol;
}

bool matricesNear(const SwfMatrix &a, const SwfMatrix &b, std::int32_t tol)
{
	return nearFixed(a.hasScale ? a.scaleX : 65536, b.hasScale ? b.scaleX : 65536, tol) &&
		nearFixed(a.hasScale ? a.scaleY : 65536, b.hasScale ? b.scaleY : 65536, tol) &&
		nearFixed(a.hasRotate ? a.rotateSkew0 : 0, b.hasRotate ? b.rotateSkew0 : 0, tol) &&
		nearFixed(a.hasRotate ? a.rotateSkew1 : 0, b.hasRotate ? b.rotateSkew1 : 0, tol) && nearFixed(a.translateX, b.translateX, tol) &&
		nearFixed(a.translateY, b.translateY, tol);
}

} // namespace

bool shapesEquivalent(const std::vector<std::uint8_t> &a, const std::vector<std::uint8_t> &b, std::int32_t matrixTolerance, std::string *why)
{
	auto no = [&](const std::string &m) {
		if (why)
		{
			*why = m;
		}
		return false;
	};
	ShapeDrawing da, db;
	if (!decodeShape3(a, da) || !decodeShape3(b, db))
	{
		return no("does not decode as a DefineShape3 the converter understands");
	}
	if (da.id != db.id)
	{
		return no("the shape id changed");
	}
	for (int k = 0; k < 4; ++k)
	{
		if (da.bounds[k] != db.bounds[k])
		{
			return no("the bounds changed");
		}
	}
	// layers without paths draw nothing (an encoder may keep or drop them)
	auto drawn = [](const ShapeDrawing &d) {
		std::vector<const ShapeLayer *> v;
		for (const ShapeLayer &l : d.layers)
		{
			if (!l.paths.empty())
			{
				v.push_back(&l);
			}
		}
		return v;
	};
	const std::vector<const ShapeLayer *> la = drawn(da), lb = drawn(db);
	if (la.size() != lb.size())
	{
		return no("the number of style layers changed");
	}
	for (std::size_t i = 0; i < la.size(); ++i)
	{
		const ShapeLayer &x = *la[i], &y = *lb[i];
		if (x.fills.size() != y.fills.size() || x.lines != y.lines || x.paths.size() != y.paths.size())
		{
			return no("layer " + std::to_string(i) + ": styles or paths changed");
		}
		for (std::size_t s = 0; s < x.fills.size(); ++s)
		{
			const ShapeStyle &p = x.fills[s], &q = y.fills[s];
			if (p.type != q.type || p.raw != q.raw || p.bitmapId != q.bitmapId || !matricesNear(p.matrix, q.matrix, matrixTolerance))
			{
				return no("layer " + std::to_string(i) + ": fill style " + std::to_string(s + 1) + " changed");
			}
		}
		for (std::size_t p = 0; p < x.paths.size(); ++p)
		{
			const ShapePath &u = x.paths[p], &v = y.paths[p];
			if (u.x != v.x || u.y != v.y || u.fill0 != v.fill0 || u.fill1 != v.fill1 || u.line != v.line || u.points != v.points)
			{
				return no("layer " + std::to_string(i) + ": path " + std::to_string(p) + " changed");
			}
		}
	}
	return true;
}

std::vector<std::uint8_t> encodePlaceObject2(const SwfPlaceObject2 &p)
{
	SwfWriter w;
	w.u8(p.flags);
	w.u16(p.depth);
	if (p.flags & 0x02)
	{
		w.u16(p.characterId);
	}
	if (p.flags & 0x04)
	{
		w.matrix(p.matrix);
	}
	if (p.flags & 0x08)
	{
		w.cxformWithAlpha(p.cxform);
	}
	if (p.flags & 0x10)
	{
		w.u16(p.ratio);
	}
	if (p.flags & 0x20)
	{
		w.cstring(p.name);
	}
	if (p.flags & 0x40)
	{
		w.u16(p.clipDepth);
	}
	if (p.flags & 0x80)
	{
		w.raw(p.clipActions);
	}
	return w.bytes;
}

bool decodePlaceObject2(const std::vector<std::uint8_t> &body, SwfPlaceObject2 &out)
{
	out = SwfPlaceObject2();
	SwfReader r(body.data(), body.size());
	out.flags = r.u8();
	out.depth = r.u16();
	if (out.flags & 0x02)
	{
		out.characterId = r.u16();
	}
	if (out.flags & 0x04)
	{
		out.matrix = r.matrix();
	}
	if (out.flags & 0x08)
	{
		out.cxform = r.cxformWithAlpha();
	}
	if (out.flags & 0x10)
	{
		out.ratio = r.u16();
	}
	if (out.flags & 0x20)
	{
		out.name = r.cstring();
	}
	if (out.flags & 0x40)
	{
		out.clipDepth = r.u16();
	}
	if (out.flags & 0x80)
	{
		out.clipActions = r.bytes(body.size() - r.pos());
	}
	return r.ok();
}

std::vector<std::uint8_t> encodeEditText(const SwfEditText &t)
{
	SwfWriter w;
	w.u16(t.id);
	w.rect(t.bounds[0], t.bounds[1], t.bounds[2], t.bounds[3]);
	w.u8(t.flags1);
	w.u8(t.flags2);
	if (t.flags1 & 0x01)
	{
		w.u16(t.fontId);
	}
	if (t.flags2 & 0x80)
	{
		w.cstring(t.fontClass);
	}
	if ((t.flags1 & 0x01) || (t.flags2 & 0x80))
	{
		w.u16(t.fontHeight);
	}
	if (t.flags1 & 0x04)
	{
		for (int k = 0; k < 4; ++k)
		{
			w.u8(t.color[k]);
		}
	}
	if (t.flags1 & 0x02)
	{
		w.u16(t.maxLength);
	}
	if (t.flags2 & 0x20)
	{
		w.u8(t.align);
		w.u16(t.leftMargin);
		w.u16(t.rightMargin);
		w.u16(t.indent);
		w.u16((std::uint16_t)t.leading);
	}
	w.cstring(t.variableName);
	if (t.flags1 & 0x80)
	{
		w.cstring(t.initialText);
	}
	return w.bytes;
}

bool decodeEditText(const std::vector<std::uint8_t> &body, SwfEditText &out)
{
	out = SwfEditText();
	SwfReader r(body.data(), body.size());
	out.id = r.u16();
	r.rect(out.bounds);
	out.flags1 = r.u8();
	out.flags2 = r.u8();
	if (out.flags1 & 0x01)
	{
		out.fontId = r.u16();
	}
	if (out.flags2 & 0x80)
	{
		out.fontClass = r.cstring();
	}
	if ((out.flags1 & 0x01) || (out.flags2 & 0x80))
	{
		out.fontHeight = r.u16();
	}
	if (out.flags1 & 0x04)
	{
		for (int k = 0; k < 4; ++k)
		{
			out.color[k] = r.u8();
		}
	}
	if (out.flags1 & 0x02)
	{
		out.maxLength = r.u16();
	}
	if (out.flags2 & 0x20)
	{
		out.align = r.u8();
		out.leftMargin = r.u16();
		out.rightMargin = r.u16();
		out.indent = r.u16();
		out.leading = (std::int16_t)r.u16();
	}
	out.variableName = r.cstring();
	if (out.flags1 & 0x80)
	{
		out.initialText = r.cstring();
	}
	return r.ok();
}

std::vector<std::uint8_t> encodeButton2(const SwfButton2 &b)
{
	SwfWriter w;
	w.u16(b.id);
	w.u8(b.flags);
	const std::size_t offsetAt = w.bytes.size();
	w.u16(0);
	for (const SwfButtonRecord &rec : b.records)
	{
		w.u8(rec.flags & 0x0F);
		w.u16(rec.characterId);
		w.u16(rec.depth);
		w.matrix(rec.matrix);
		w.cxformWithAlpha(rec.cxform);
	}
	w.u8(0);
	if (!b.condActions.empty())
	{
		const std::size_t offset = w.bytes.size() - offsetAt;
		w.bytes[offsetAt] = (std::uint8_t)offset;
		w.bytes[offsetAt + 1] = (std::uint8_t)(offset >> 8);
		w.raw(b.condActions);
	}
	return w.bytes;
}

bool decodeButton2(const std::vector<std::uint8_t> &body, SwfButton2 &out)
{
	out = SwfButton2();
	SwfReader r(body.data(), body.size());
	out.id = r.u16();
	out.flags = r.u8();
	const std::size_t offsetAt = r.pos();
	const std::uint16_t actionOffset = r.u16();
	for (;;)
	{
		const std::uint8_t f = r.u8();
		if (!r.ok())
		{
			return false;
		}
		if (f == 0)
		{
			break;
		}
		if (f & 0x30)
		{
			return false; // blend mode / filter list (SWF 8): never written by the converter
		}
		SwfButtonRecord rec;
		rec.flags = f;
		rec.characterId = r.u16();
		rec.depth = r.u16();
		rec.matrix = r.matrix();
		rec.cxform = r.cxformWithAlpha();
		out.records.push_back(rec);
	}
	if (actionOffset != 0)
	{
		if (offsetAt + actionOffset > body.size())
		{
			return false;
		}
		out.condActions.assign(body.begin() + (std::ptrdiff_t)(offsetAt + actionOffset), body.end());
	}
	return r.ok();
}

} // namespace aptswf
