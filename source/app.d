import std.stdio;
import std.conv;
import std.outbuffer;
import libclang;

string toString(CXString cxs)
{
	auto p = clang_getCString(cxs);
	return to!string(cast(immutable char*) p);
}

string getCursorKindName(CXCursorKind cursorKind)
{
	auto kindName = clang_getCursorKindSpelling(cursorKind);
	scope (exit)
		clang_disposeString(kindName);

	return toString(kindName);
}

string getCursorSpelling(CXCursor cursor)
{
	auto cursorSpelling = clang_getCursorSpelling(cursor);
	scope (exit)
		clang_disposeString(cursorSpelling);

	return toString(cursorSpelling);
}

string getCursorTypeKindName(CXTypeKind typeKind)
{
	auto kindName = clang_getTypeKindSpelling(typeKind);
	scope (exit)
		clang_disposeString(kindName);

	return toString(kindName);
}

class Type
{

}

class Primitive : Type
{
	CXTypeKind m_kind;

	this(CXTypeKind kind)
	{
		m_kind = kind;
	}
}

class Typedef : Type
{
	string m_name;
	Type m_type;

	this(string name, Type type)
	{
		m_name = name;
		m_type = type;
	}
}

struct Context
{
	int level;
	bool isExternC;

	string getIndent()
	{
		auto buf = new OutBuffer();
		for (int i = 0; i < level; ++i)
		{
			buf.write("  ");
		}
		return buf.toString();
	}

	Context getChild()
	{
		return Context(level + 1, isExternC);
	}

	CXToken[] getTokens(CXCursor cursor)
	{
		auto extent = clang_getCursorExtent(cursor);
		auto begin = clang_getRangeStart(extent);
		auto end = clang_getRangeEnd(extent);
		auto range = clang_getRange(begin, end);

		CXToken* tokens;
		uint num;
		auto tu = clang_Cursor_getTranslationUnit(cursor);
		clang_tokenize(tu, range, &tokens, &num);

		return tokens[0 .. num];
	}

	Type[] stack;
	Type[uint] typeMap;

	CXCursor getRootCanonical(CXCursor cursor)
	{
		auto current = cursor;
		while (true)
		{
			auto canonical = clang_getCanonicalCursor(current);
			if (canonical == current)
			{
				return current;
			}
			current = canonical;
		}
	}

	void pushTypedef(CXCursor cursor)
	{
		auto hash = clang_hashCursor(cursor);
		auto type = clang_getTypedefDeclUnderlyingType(cursor);
		auto kind = getCursorTypeKindName(type.kind);
		switch (type.kind)
		{
		case CXTypeKind.CXType_ULongLong:
			{
				auto name = getCursorSpelling(cursor);
				auto decl = new Typedef(name, new Primitive(type.kind));
				typeMap[hash] = decl;
				stack ~= decl;
			}
			break;

		default:
			throw new Exception("not implemented");
		}
		// scope (exit)
		// 	clang_disposeString(type);
	}
}

extern (C) CXChildVisitResult visitor(CXCursor cursor, CXCursor /* parent */ ,
		Context* parentContext)
{
	auto context = parentContext.getChild();
	auto tu = clang_Cursor_getTranslationUnit(cursor);
	auto cursorKind = cast(CXCursorKind) clang_getCursorKind(cursor);
	auto kind = getCursorKindName(cursorKind);
	switch (cursorKind)
	{
	case CXCursorKind.CXCursor_InclusionDirective:
	case CXCursorKind.CXCursor_MacroDefinition:
	case CXCursorKind.CXCursor_MacroExpansion:
		// skip
		break;

	case CXCursorKind.CXCursor_UnexposedDecl:
		{
			auto tokens = context.getTokens(cursor);
			scope (exit)
				clang_disposeTokens(tu, tokens.ptr, cast(uint) tokens.length);

			if (tokens.length >= 2)
			{
				// extern C
				auto token0 = toString(clang_getTokenSpelling(tu, tokens[0]));
				auto token1 = toString(clang_getTokenSpelling(tu, tokens[1]));
				if (token0 == "extern" && token1 == "\"C\"")
				{
					context.isExternC = true;
				}
			}
		}
		clang_visitChildren(cursor, &visitor, &context);
		break;

	case CXCursorKind.CXCursor_TypedefDecl:
		context.pushTypedef(cursor);
		clang_visitChildren(cursor, &visitor, &context);
		break;

	default:
		return CXChildVisitResult.CXChildVisit_Break;
	}

	return CXChildVisitResult.CXChildVisit_Continue;
}

int main(string[] args)
{
	if (args.length < 2)
	{
		return 1;
	}

	auto index = clang_createIndex(0, 1);
	scope (exit)
		clang_disposeIndex(index);

	auto params = [
		cast(byte*) "-x".ptr, cast(byte*) "c++".ptr,
		cast(byte*) "-IC:/Program Files/LLVM/include".ptr
	];
	auto tu = clang_createTranslationUnitFromSourceFile(index,
			cast(byte*) "C:/Program Files/LLVM/include/clang-c/Index.h".ptr,
			cast(int) params.length, params.ptr, 0, null);
	if (!tu)
	{
		return 2;
	}
	scope (exit)
		clang_disposeTranslationUnit(tu);

	Context context;
	auto rootCursor = clang_getTranslationUnitCursor(tu);
	clang_visitChildren(rootCursor, &visitor, &context);

	return 0;
}
