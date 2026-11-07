// OpenBFME. GPL-3.0.
// See AptSwfFormat.h.

#include "Libraries/Source/Apt/AptSwfFormat.h"

#include "Common/Sha256.h"

#include <cmath>
#include <cstring>

namespace aptswf
{

// =============================================================================================================================
// writer
// =============================================================================================================================

void SwfWriter::u8(std::uint32_t v)
{
	align();
	bytes.push_back((std::uint8_t)v);
}

void SwfWriter::u16(std::uint32_t v)
{
	align();
	bytes.push_back((std::uint8_t)v);
	bytes.push_back((std::uint8_t)(v >> 8));
}

void SwfWriter::u32(std::uint32_t v)
{
	align();
	for (int i = 0; i < 4; ++i)
	{
		bytes.push_back((std::uint8_t)(v >> (8 * i)));
	}
}

void SwfWriter::f32(float v)
{
	std::uint32_t bits;
	std::memcpy(&bits, &v, 4);
	u32(bits);
}

void SwfWriter::cstring(const std::string &s)
{
	align();
	bytes.insert(bytes.end(), s.begin(), s.end());
	bytes.push_back(0);
}

void SwfWriter::raw(const std::vector<std::uint8_t> &b)
{
	raw(b.data(), b.size());
}

void SwfWriter::raw(const std::uint8_t *p, std::size_t n)
{
	align();
	bytes.insert(bytes.end(), p, p + n);
}

void SwfWriter::ub(int bits, std::uint32_t v)
{
	for (int i = bits - 1; i >= 0; --i)
	{
		m_bitBuf = (m_bitBuf << 1) | ((v >> i) & 1u);
		if (++m_bitCount == 8)
		{
			bytes.push_back((std::uint8_t)m_bitBuf);
			m_bitBuf = 0;
			m_bitCount = 0;
		}
	}
}

void SwfWriter::sb(int bits, std::int32_t v)
{
	ub(bits, (std::uint32_t)v);
}

void SwfWriter::align()
{
	if (m_bitCount > 0)
	{
		bytes.push_back((std::uint8_t)(m_bitBuf << (8 - m_bitCount)));
		m_bitBuf = 0;
		m_bitCount = 0;
	}
}

int swfSignedBits(std::int32_t v)
{
	// the smallest n with -2^(n-1) <= v < 2^(n-1)
	int n = 1;
	while (n < 32)
	{
		const std::int64_t lo = -((std::int64_t)1 << (n - 1)), hi = ((std::int64_t)1 << (n - 1)) - 1;
		if (v >= lo && v <= hi)
		{
			break;
		}
		++n;
	}
	return n;
}

int swfUnsignedBits(std::uint32_t v)
{
	int n = 0;
	while (v)
	{
		++n;
		v >>= 1;
	}
	return n;
}

void SwfWriter::rect(std::int32_t xmin, std::int32_t xmax, std::int32_t ymin, std::int32_t ymax)
{
	align();
	int n = 1;
	for (std::int32_t v : { xmin, xmax, ymin, ymax })
	{
		n = std::max(n, swfSignedBits(v));
	}
	ub(5, (std::uint32_t)n);
	sb(n, xmin);
	sb(n, xmax);
	sb(n, ymin);
	sb(n, ymax);
	align();
}

void SwfWriter::matrix(const SwfMatrix &m)
{
	align();
	ub(1, m.hasScale ? 1 : 0);
	if (m.hasScale)
	{
		const int n = std::max(swfSignedBits(m.scaleX), swfSignedBits(m.scaleY));
		ub(5, (std::uint32_t)n);
		sb(n, m.scaleX);
		sb(n, m.scaleY);
	}
	ub(1, m.hasRotate ? 1 : 0);
	if (m.hasRotate)
	{
		const int n = std::max(swfSignedBits(m.rotateSkew0), swfSignedBits(m.rotateSkew1));
		ub(5, (std::uint32_t)n);
		sb(n, m.rotateSkew0);
		sb(n, m.rotateSkew1);
	}
	const int n = (m.translateX == 0 && m.translateY == 0) ? 0 : std::max(swfSignedBits(m.translateX), swfSignedBits(m.translateY));
	ub(5, (std::uint32_t)n);
	if (n)
	{
		sb(n, m.translateX);
		sb(n, m.translateY);
	}
	align();
}

void SwfWriter::cxformWithAlpha(const SwfCxform &c)
{
	align();
	ub(1, c.hasAdd ? 1 : 0);
	ub(1, c.hasMult ? 1 : 0);
	int n = 1;
	for (int i = 0; i < 4; ++i)
	{
		if (c.hasMult)
		{
			n = std::max(n, swfSignedBits(c.mult[i]));
		}
		if (c.hasAdd)
		{
			n = std::max(n, swfSignedBits(c.add[i]));
		}
	}
	ub(4, (std::uint32_t)n);
	if (c.hasMult)
	{
		for (int i = 0; i < 4; ++i)
		{
			sb(n, c.mult[i]);
		}
	}
	if (c.hasAdd)
	{
		for (int i = 0; i < 4; ++i)
		{
			sb(n, c.add[i]);
		}
	}
	align();
}

bool SwfMatrix::operator==(const SwfMatrix &o) const
{
	// compare the effective values (a missing scale is 1.0, a missing rotate 0)
	const std::int32_t a0 = hasScale ? scaleX : 65536, d0 = hasScale ? scaleY : 65536, a1 = o.hasScale ? o.scaleX : 65536, d1 = o.hasScale ? o.scaleY : 65536;
	const std::int32_t b0 = hasRotate ? rotateSkew0 : 0, c0 = hasRotate ? rotateSkew1 : 0, b1 = o.hasRotate ? o.rotateSkew0 : 0, c1 = o.hasRotate ? o.rotateSkew1 : 0;
	return a0 == a1 && d0 == d1 && b0 == b1 && c0 == c1 && translateX == o.translateX && translateY == o.translateY;
}

bool SwfCxform::operator==(const SwfCxform &o) const
{
	for (int i = 0; i < 4; ++i)
	{
		const std::int32_t m0 = hasMult ? mult[i] : 256, m1 = o.hasMult ? o.mult[i] : 256;
		const std::int32_t a0 = hasAdd ? add[i] : 0, a1 = o.hasAdd ? o.add[i] : 0;
		if (m0 != m1 || a0 != a1)
		{
			return false;
		}
	}
	return true;
}

std::int32_t swfFixed16(float v)
{
	return (std::int32_t)std::lround((double)v * 65536.0);
}

std::int32_t swfTwips(float pixels)
{
	return (std::int32_t)std::lround((double)pixels * 20.0);
}

SwfMatrix swfMatrixFromFloats(float a, float b, float c, float d, float tx, float ty)
{
	SwfMatrix m;
	m.scaleX = swfFixed16(a);
	m.scaleY = swfFixed16(d);
	m.hasScale = m.scaleX != 65536 || m.scaleY != 65536;
	m.rotateSkew0 = swfFixed16(b);
	m.rotateSkew1 = swfFixed16(c);
	m.hasRotate = m.rotateSkew0 != 0 || m.rotateSkew1 != 0;
	m.translateX = swfTwips(tx);
	m.translateY = swfTwips(ty);
	return m;
}

void swfMatrixToFloats(const SwfMatrix &m, float out[6])
{
	out[0] = m.hasScale ? (float)(m.scaleX / 65536.0) : 1.0f;
	out[1] = m.hasRotate ? (float)(m.rotateSkew0 / 65536.0) : 0.0f;
	out[2] = m.hasRotate ? (float)(m.rotateSkew1 / 65536.0) : 0.0f;
	out[3] = m.hasScale ? (float)(m.scaleY / 65536.0) : 1.0f;
	out[4] = (float)(m.translateX / 20.0);
	out[5] = (float)(m.translateY / 20.0);
}

std::vector<std::uint8_t> swfSpriteBody(std::uint16_t spriteId, std::uint16_t frameCount, const std::vector<SwfTag> &children)
{
	SwfWriter w;
	w.u16(spriteId);
	w.u16(frameCount);
	for (const SwfTag &t : children)
	{
		swfWriteTag(w, t);
	}
	w.u16(0); // End
	return w.bytes;
}

void swfWriteTag(SwfWriter &w, const SwfTag &tag)
{
	const std::vector<std::uint8_t> *body = &tag.body;
	std::vector<std::uint8_t> spriteBody;
	if (tag.code == SWF_TAG_DEFINESPRITE)
	{
		// body holds the 4-byte id + frame count prefix; the children (and the sprite's End) follow
		spriteBody.assign(tag.body.begin(), tag.body.begin() + std::min<std::size_t>(4, tag.body.size()));
		SwfWriter cw;
		for (const SwfTag &t : tag.children)
		{
			swfWriteTag(cw, t);
		}
		cw.u16(0);
		spriteBody.insert(spriteBody.end(), cw.bytes.begin(), cw.bytes.end());
		body = &spriteBody;
	}
	const std::size_t len = body->size();
	if (len < 63 && !tag.forceLong)
	{
		w.u16((std::uint32_t)(tag.code << 6) | (std::uint32_t)len);
	}
	else
	{
		w.u16((std::uint32_t)(tag.code << 6) | 0x3F);
		w.u32((std::uint32_t)len);
	}
	w.raw(*body);
}

std::vector<std::uint8_t> swfWriteFile(const SwfHeader &header, const std::vector<SwfTag> &tags)
{
	SwfWriter body;
	body.rect(0, header.frameWidthTwips, 0, header.frameHeightTwips);
	body.u16(header.frameRate8_8);
	body.u16(header.frameCount);
	for (const SwfTag &t : tags)
	{
		swfWriteTag(body, t);
	}
	body.u16(0); // End
	SwfWriter w;
	w.u8('F');
	w.u8('W');
	w.u8('S');
	w.u8(header.version);
	w.u32((std::uint32_t)(8 + body.bytes.size()));
	w.raw(body.bytes);
	return w.bytes;
}

// =============================================================================================================================
// reader
// =============================================================================================================================

bool SwfReader::need(std::size_t n)
{
	if (!m_ok || m_pos + n > m_size)
	{
		m_ok = false;
		return false;
	}
	return true;
}

std::uint8_t SwfReader::u8()
{
	align();
	return need(1) ? m_data[m_pos++] : 0;
}

std::uint16_t SwfReader::u16()
{
	align();
	if (!need(2))
	{
		return 0;
	}
	std::uint16_t v = (std::uint16_t)(m_data[m_pos] | (m_data[m_pos + 1] << 8));
	m_pos += 2;
	return v;
}

std::uint32_t SwfReader::u32()
{
	align();
	if (!need(4))
	{
		return 0;
	}
	std::uint32_t v = (std::uint32_t)m_data[m_pos] | ((std::uint32_t)m_data[m_pos + 1] << 8) | ((std::uint32_t)m_data[m_pos + 2] << 16) |
		((std::uint32_t)m_data[m_pos + 3] << 24);
	m_pos += 4;
	return v;
}

float SwfReader::f32()
{
	std::uint32_t b = u32();
	float f;
	std::memcpy(&f, &b, 4);
	return f;
}

std::string SwfReader::cstring()
{
	align();
	std::string s;
	while (need(1))
	{
		char c = (char)m_data[m_pos++];
		if (c == 0)
		{
			return s;
		}
		s.push_back(c);
	}
	return s;
}

std::vector<std::uint8_t> SwfReader::bytes(std::size_t n)
{
	align();
	if (!need(n))
	{
		return {};
	}
	std::vector<std::uint8_t> v(m_data + m_pos, m_data + m_pos + n);
	m_pos += n;
	return v;
}

std::uint32_t SwfReader::ub(int bits)
{
	std::uint32_t v = 0;
	for (int i = 0; i < bits; ++i)
	{
		if (m_bitCount == 0)
		{
			if (!need(1))
			{
				return 0;
			}
			m_bitByte = m_data[m_pos++];
			m_bitCount = 8;
		}
		--m_bitCount;
		v = (v << 1) | ((m_bitByte >> m_bitCount) & 1u);
	}
	return v;
}

std::int32_t SwfReader::sb(int bits)
{
	if (bits == 0)
	{
		return 0;
	}
	std::uint32_t v = ub(bits);
	if (bits < 32 && (v & (1u << (bits - 1))))
	{
		v |= ~((1u << bits) - 1);
	}
	return (std::int32_t)v;
}

void SwfReader::rect(std::int32_t out[4])
{
	align();
	int n = (int)ub(5);
	for (int i = 0; i < 4; ++i)
	{
		out[i] = sb(n);
	}
	align();
}

SwfMatrix SwfReader::matrix()
{
	align();
	SwfMatrix m;
	m.hasScale = ub(1) != 0;
	if (m.hasScale)
	{
		int n = (int)ub(5);
		m.scaleX = sb(n);
		m.scaleY = sb(n);
	}
	m.hasRotate = ub(1) != 0;
	if (m.hasRotate)
	{
		int n = (int)ub(5);
		m.rotateSkew0 = sb(n);
		m.rotateSkew1 = sb(n);
	}
	int n = (int)ub(5);
	m.translateX = sb(n);
	m.translateY = sb(n);
	align();
	return m;
}

SwfCxform SwfReader::cxformWithAlpha()
{
	align();
	SwfCxform c;
	c.hasAdd = ub(1) != 0;
	c.hasMult = ub(1) != 0;
	int n = (int)ub(4);
	if (c.hasMult)
	{
		for (int i = 0; i < 4; ++i)
		{
			c.mult[i] = sb(n);
		}
	}
	if (c.hasAdd)
	{
		for (int i = 0; i < 4; ++i)
		{
			c.add[i] = sb(n);
		}
	}
	align();
	return c;
}

bool swfReadTags(const std::uint8_t *data, std::size_t size, std::vector<SwfTag> &out, std::string *error)
{
	SwfReader r(data, size);
	while (!r.atEnd())
	{
		std::uint16_t head = r.u16();
		std::uint32_t len = head & 0x3F;
		SwfTag t;
		t.code = (std::uint16_t)(head >> 6);
		if (len == 0x3F)
		{
			len = r.u32();
			t.forceLong = true;
		}
		if (!r.ok() || r.pos() + len > r.size())
		{
			if (error)
			{
				*error = "SWF tag " + std::to_string(t.code) + " at " + std::to_string(r.pos()) + " runs past the end of its stream";
			}
			return false;
		}
		if (t.code == SWF_TAG_END)
		{
			return true;
		}
		t.body = r.bytes(len);
		if (t.code == SWF_TAG_DEFINESPRITE && t.body.size() >= 4)
		{
			if (!swfReadTags(t.body.data() + 4, t.body.size() - 4, t.children, error))
			{
				return false;
			}
			t.body.resize(4);
		}
		out.push_back(std::move(t));
	}
	return true; // a stream without End (tolerated, as players do)
}

bool swfReadFile(const std::vector<std::uint8_t> &bytes, SwfFile &out, std::string *error)
{
	auto fail = [&](const std::string &m) {
		if (error)
		{
			*error = m;
		}
		return false;
	};
	if (bytes.size() < 8)
	{
		return fail("SWF: file shorter than its header");
	}
	const std::uint8_t sig = bytes[0];
	if (bytes[1] != 'W' || bytes[2] != 'S' || (sig != 'F' && sig != 'C' && sig != 'Z'))
	{
		return fail("SWF: bad signature");
	}
	if (sig == 'Z')
	{
		return fail("SWF: LZMA-compressed (ZWS) files are not supported; save the file uncompressed or zlib-compressed");
	}
	out = SwfFile();
	out.header.version = bytes[3];
	const std::uint32_t declared = (std::uint32_t)bytes[4] | ((std::uint32_t)bytes[5] << 8) | ((std::uint32_t)bytes[6] << 16) | ((std::uint32_t)bytes[7] << 24);
	std::vector<std::uint8_t> body;
	if (sig == 'C')
	{
		out.compressed = true;
		std::string e;
		if (!zlibInflate(bytes.data() + 8, bytes.size() - 8, body, &e))
		{
			return fail("SWF: " + e);
		}
	}
	else
	{
		body.assign(bytes.begin() + 8, bytes.end());
	}
	if (body.size() + 8 != declared)
	{
		return fail("SWF: header length " + std::to_string(declared) + " does not match the file (" + std::to_string(body.size() + 8) + ")");
	}
	SwfReader r(body.data(), body.size());
	std::int32_t rc[4];
	r.rect(rc);
	out.header.frameWidthTwips = rc[1];
	out.header.frameHeightTwips = rc[3];
	out.header.frameRate8_8 = r.u16();
	out.header.frameCount = r.u16();
	if (!r.ok())
	{
		return fail("SWF: truncated header");
	}
	return swfReadTags(body.data() + r.pos(), body.size() - r.pos(), out.tags, error);
}

// =============================================================================================================================
// zlib
// =============================================================================================================================

namespace
{

std::uint32_t adler32(const std::uint8_t *p, std::size_t n)
{
	std::uint32_t a = 1, b = 0;
	for (std::size_t i = 0; i < n; ++i)
	{
		a = (a + p[i]) % 65521u;
		b = (b + a) % 65521u;
	}
	return (b << 16) | a;
}

// Inflate after Mark Adler's puff.c (zlib contrib, public domain): canonical Huffman decoding, stored / fixed / dynamic blocks.
struct Inflater
{
	const std::uint8_t *in;
	std::size_t inLen;
	std::size_t inPos = 0;
	std::uint32_t bitBuf = 0;
	int bitCnt = 0;
	std::vector<std::uint8_t> &out;
	bool bad = false;

	Inflater(const std::uint8_t *p, std::size_t n, std::vector<std::uint8_t> &o) : in(p), inLen(n), out(o) {}

	int bits(int need)
	{
		std::uint32_t val = bitBuf;
		while (bitCnt < need)
		{
			if (inPos >= inLen)
			{
				bad = true;
				return 0;
			}
			val |= (std::uint32_t)in[inPos++] << bitCnt;
			bitCnt += 8;
		}
		bitBuf = val >> need;
		bitCnt -= need;
		return (int)(val & ((1u << need) - 1));
	}

	struct Huffman
	{
		short count[16];
		short symbol[288];
	};

	int decode(const Huffman &h)
	{
		int code = 0, first = 0, index = 0;
		for (int len = 1; len <= 15; ++len)
		{
			code |= bits(1);
			if (bad)
			{
				return -1;
			}
			int count = h.count[len];
			if (code - count < first)
			{
				return h.symbol[index + (code - first)];
			}
			index += count;
			first += count;
			first <<= 1;
			code <<= 1;
		}
		bad = true;
		return -1;
	}

	static int construct(Huffman &h, const short *length, int n)
	{
		for (int len = 0; len <= 15; ++len)
		{
			h.count[len] = 0;
		}
		for (int s = 0; s < n; ++s)
		{
			h.count[length[s]]++;
		}
		if (h.count[0] == n)
		{
			return 0;
		}
		int left = 1;
		for (int len = 1; len <= 15; ++len)
		{
			left <<= 1;
			left -= h.count[len];
			if (left < 0)
			{
				return left;
			}
		}
		short offs[16];
		offs[1] = 0;
		for (int len = 1; len < 15; ++len)
		{
			offs[len + 1] = (short)(offs[len] + h.count[len]);
		}
		for (int s = 0; s < n; ++s)
		{
			if (length[s] != 0)
			{
				h.symbol[offs[length[s]]++] = (short)s;
			}
		}
		return left;
	}

	bool codes(const Huffman &lencode, const Huffman &distcode)
	{
		static const short lbase[29] = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 };
		static const short lext[29] = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 };
		static const short dbase[30] = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097,
			6145, 8193, 12289, 16385, 24577 };
		static const short dext[30] = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 };
		for (;;)
		{
			int symbol = decode(lencode);
			if (symbol < 0)
			{
				return false;
			}
			if (symbol < 256)
			{
				out.push_back((std::uint8_t)symbol);
			}
			else if (symbol == 256)
			{
				return true;
			}
			else
			{
				symbol -= 257;
				if (symbol >= 29)
				{
					return false;
				}
				int len = lbase[symbol] + bits(lext[symbol]);
				int ds = decode(distcode);
				if (ds < 0 || ds >= 30)
				{
					return false;
				}
				std::size_t dist = (std::size_t)(dbase[ds] + bits(dext[ds]));
				if (bad || dist > out.size())
				{
					return false;
				}
				std::size_t from = out.size() - dist;
				for (int i = 0; i < len; ++i)
				{
					out.push_back(out[from + (std::size_t)i]);
				}
			}
		}
	}

	bool stored()
	{
		bitBuf = 0;
		bitCnt = 0;
		if (inPos + 4 > inLen)
		{
			return false;
		}
		unsigned len = in[inPos] | (in[inPos + 1] << 8);
		unsigned nlen = in[inPos + 2] | (in[inPos + 3] << 8);
		inPos += 4;
		if (len != (~nlen & 0xffffu) || inPos + len > inLen)
		{
			return false;
		}
		out.insert(out.end(), in + inPos, in + inPos + len);
		inPos += len;
		return true;
	}

	bool fixed()
	{
		static Huffman lencode, distcode;
		static bool built = false;
		if (!built)
		{
			short lengths[288];
			int s = 0;
			for (; s < 144; ++s) lengths[s] = 8;
			for (; s < 256; ++s) lengths[s] = 9;
			for (; s < 280; ++s) lengths[s] = 7;
			for (; s < 288; ++s) lengths[s] = 8;
			construct(lencode, lengths, 288);
			for (s = 0; s < 30; ++s) lengths[s] = 5;
			construct(distcode, lengths, 30);
			built = true;
		}
		return codes(lencode, distcode);
	}

	bool dynamic()
	{
		static const short order[19] = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };
		short lengths[320];
		int nlen = bits(5) + 257, ndist = bits(5) + 1, ncode = bits(4) + 4;
		if (bad || nlen > 286 || ndist > 30)
		{
			return false;
		}
		int index = 0;
		for (; index < ncode; ++index) lengths[order[index]] = (short)bits(3);
		for (; index < 19; ++index) lengths[order[index]] = 0;
		Huffman lencode, distcode;
		if (construct(lencode, lengths, 19) != 0)
		{
			return false;
		}
		index = 0;
		while (index < nlen + ndist)
		{
			int symbol = decode(lencode);
			if (symbol < 0)
			{
				return false;
			}
			if (symbol < 16)
			{
				lengths[index++] = (short)symbol;
			}
			else
			{
				int len = 0;
				if (symbol == 16)
				{
					if (index == 0)
					{
						return false;
					}
					len = lengths[index - 1];
					symbol = 3 + bits(2);
				}
				else if (symbol == 17)
				{
					symbol = 3 + bits(3);
				}
				else
				{
					symbol = 11 + bits(7);
				}
				if (index + symbol > nlen + ndist)
				{
					return false;
				}
				while (symbol--) lengths[index++] = (short)len;
			}
		}
		if (lengths[256] == 0)
		{
			return false;
		}
		int err = construct(lencode, lengths, nlen);
		if (err < 0 || (err > 0 && nlen - lencode.count[0] != 1))
		{
			return false;
		}
		err = construct(distcode, lengths + nlen, ndist);
		if (err < 0 || (err > 0 && ndist - distcode.count[0] != 1))
		{
			return false;
		}
		return codes(lencode, distcode);
	}

	bool run()
	{
		int last;
		do
		{
			last = bits(1);
			int type = bits(2);
			if (bad)
			{
				return false;
			}
			bool ok = type == 0 ? stored() : type == 1 ? fixed() : type == 2 ? dynamic() : false;
			if (!ok || bad)
			{
				return false;
			}
		} while (!last);
		return true;
	}
};

} // namespace

std::vector<std::uint8_t> zlibStore(const std::uint8_t *data, std::size_t size)
{
	std::vector<std::uint8_t> z;
	z.push_back(0x78);
	z.push_back(0x01);
	std::size_t pos = 0;
	do
	{
		const std::size_t n = std::min<std::size_t>(65535, size - pos);
		const bool last = pos + n == size;
		z.push_back(last ? 1 : 0);
		z.push_back((std::uint8_t)n);
		z.push_back((std::uint8_t)(n >> 8));
		z.push_back((std::uint8_t)~n);
		z.push_back((std::uint8_t)(~n >> 8));
		z.insert(z.end(), data + pos, data + pos + n);
		pos += n;
	} while (pos < size);
	const std::uint32_t a = adler32(data, size);
	z.push_back((std::uint8_t)(a >> 24));
	z.push_back((std::uint8_t)(a >> 16));
	z.push_back((std::uint8_t)(a >> 8));
	z.push_back((std::uint8_t)a);
	return z;
}

bool zlibInflate(const std::uint8_t *data, std::size_t size, std::vector<std::uint8_t> &out, std::string *error)
{
	out.clear();
	if (size < 6 || (data[0] & 0x0F) != 8 || ((data[0] << 8) | data[1]) % 31 != 0 || (data[1] & 0x20))
	{
		if (error)
		{
			*error = "zlib: bad stream header";
		}
		return false;
	}
	Inflater inf(data + 2, size - 2, out);
	if (!inf.run())
	{
		if (error)
		{
			*error = "zlib: corrupt deflate stream";
		}
		return false;
	}
	return true; // the Adler-32 trailer is not checked (players do not either)
}

std::string sha256Hex(const std::uint8_t *data, std::size_t size)
{
	const std::array<std::uint8_t, 32> h = Sha256::hash(data, size);
	return HexBytes(h.data(), h.size());
}

} // namespace aptswf
