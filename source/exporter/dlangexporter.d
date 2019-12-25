module exporter.dlangexporter;
import exporter.source;
import exporter.omitenumprefix;
import clangdecl;
import std.ascii;
import std.stdio;
import std.string;
import std.path;
import std.traits;
import std.file;
import std.experimental.logger;
import std.algorithm;
import sliceview;

///
/// D言語向けに出力する
///

immutable HEADLINE = "// This source code was generated by dclangen";

string[] escapeSymbols = ["module", "ref", "in",];

string DEscapeName(string src)
{
    if (escapeSymbols.any!(a => a == src))
    {
        return "_" ~ src;
    }
    return src;
}

Decl GetTypedefSource(Decl decl)
{
    while (true)
    {
        Typedef typedefDecl = cast(Typedef) decl;
        if (!typedefDecl)
        {
            break;
        }
        decl = typedefDecl.typeref.type;
    }
    return decl;
}

static bool isInterface(Decl decl)
{
    debug
    {
        auto userDecl = cast(UserDecl) decl;
        if (userDecl)
        {
            // if (userDecl.m_name == "ID3DBlob")
            {
                auto a = 0;
            }
        }
    }

    decl = decl.GetTypedefSource();

    Struct structDecl = cast(Struct) decl;
    if (!structDecl)
    {
        return false;
    }

    if (structDecl.definition)
    {
        // resolve forward decl
        structDecl = structDecl.definition;
    }

    return structDecl.isInterface;
}

string GetName(Decl decl)
{
    auto userDecl = cast(UserDecl) decl;
    if (!userDecl)
    {
        return "";
    }
    return userDecl.name;
}

string DPointer(Pointer p)
{
    if (p.typeref.type.GetName() == "ID3DInclude")
    {
        return "void*";
    }
    else if (isInterface(p.typeref.type))
    {
        return format("%s", DType(p.typeref.type));
    }
    else
    {
        return format("%s*", DType(p.typeref.type));
    }
}

string DArray(Array a)
{
    return format("%s[%d]", DType(a.typeref.type), a.size);
}

string DType(Decl t)
{
    return castSwitch!((Pointer decl) => DPointer(decl),
            (Array decl) => DArray(decl), (UserDecl decl) => decl.name, //
            (Void _) => "void", (Bool _) => "bool", (Int8 _) => "char",
            (Int16 _) => "short", (Int32 _) => "int", (Int64 _) => "long",
            (UInt8 _) => "ubyte", (UInt16 _) => "ushort", (UInt32 _) => "uint",
            (UInt64 _) => "ulong", (Float _) => "float", (Double _) => "double", //
            () => format("unknown(%s)", t))(t);
}

void DTypedefDecl(File* f, Typedef t)
{
    auto dst = DType(t.typeref.type);
    if (dst)
    {
        if (t.name == dst)
        {
            // f.writefln("// samename: %s", t.m_name);
            return;
        }

        f.writefln("alias %s = %s;", t.name, dst);
        return;
    }

    // nameless
    f.writeln("// typedef target nameless");
}

immutable string[] skipMethods = ["QueryInterface", "AddRef", "Release"];

void DStructDecl(File* f, Struct decl, string typedefName = null)
{
    // assert(!decl.m_forwardDecl);
    auto name = typedefName ? typedefName : decl.name;
    if (!name)
    {
        f.writeln("// struct nameless");
        return;
    }

    if (decl.isInterface)
    {
        // com interface
        if (decl.forwardDecl)
        {
            return;
        }

        // interface
        f.writef("interface %s", name);
        if (decl.base)
        {
            f.writef(": %s", decl.base.name);
        }
        f.writeln();
        f.writeln("{");
        if (!decl.iid.empty)
        {
            f.writefln("    static const iidof = parseGUID(\"%s\");", decl.iid.toString());
        }
        // methods
        foreach (method; decl.methods)
        {
            if (skipMethods.any!(a => a == method.name))
            {
                f.writefln("    // skip %s", method.name);
            }
            else
            {
                DFucntionDecl(f, method, "    ", true);
            }
        }
        f.writeln("}");
    }
    else
    {
        if (decl.forwardDecl)
        {
            // forward decl
            assert(decl.fields.empty);
            f.writefln("struct %s;", name);
        }
        else
        {

            f.writefln("struct %s", name);
            f.writeln("{");
            foreach (field; decl.fields)
            {
                auto typeName = DType(field.typeref.type);
                if (!typeName)
                {
                    auto structDecl = cast(Struct) field.typeref.type;
                    if (structDecl)
                    {
                        if (structDecl.isUnion)
                        {
                            // typedef struct D3D11_VIDEO_COLOR
                            // {
                            // union 
                            //     {
                            //     int YCbCr;
                            //     float RGBA;
                            //     } 	;
                            // }                        
                            f.writefln("    union {");
                            foreach (unionField; structDecl.fields)
                            {
                                auto unionFieldTypeName = DType(unionField.typeref.type);
                                f.writefln("        %s %s;", unionFieldTypeName,
                                        DEscapeName(unionField.name));
                            }
                            f.writefln("    }");
                        }
                        else
                        {
                            f.writefln("   // anonymous struct %s;", DEscapeName(field.name));
                        }
                    }
                    else
                    {
                        throw new Exception("unknown");
                    }
                }
                else
                {
                    f.writefln("    %s %s;", typeName, DEscapeName(field.name));
                }
            }
            f.writeln("}");
        }
    }
}

void DEnumDecl(File* f, Enum decl, bool omitEnumPrefix)
{
    if (!decl.name)
    {
        f.writeln("// enum nameless");
        return;
    }

    f.writef("enum %s", decl.name);
    auto maxValue = decl.maxValue;
    if (maxValue > uint.max)
    {
        f.write(": ulong");
    }
    f.writeln();

    if (omitEnumPrefix)
    {
        omit(decl);
    }

    f.writeln("{");
    foreach (value; decl.values)
    {
        auto name = value.name;
        f.writefln("    %s = 0x%x,", name, value.value);
    }
    f.writeln("}");
}

void DFucntionDecl(File* f, Function decl, string indent, bool isMethod)
{
    if (!isMethod && !decl.dllExport)
    {
        auto retType = cast(UserDecl) decl.ret;
        if (!retType)
        {
            return;
        }
        if (retType.name != "HRESULT")
        {
            return;
        }
        debug auto isCom = true; // D3D11CreateDevice ... etc
    }
    f.write(indent);
    if (decl.externC)
    {
        f.write("extern(C) ");
    }
    f.write(DType(decl.ret));
    f.write(" ");
    f.write(decl.name);
    f.write("(");

    auto isFirst = true;
    foreach (param; decl.params)
    {
        if (isFirst)
        {
            isFirst = false;
        }
        else
        {
            f.write(", ");
        }
        if (param.typeref.hasConstRecursive)
        {
            f.write("const ");
        }
        f.write(format("%s %s", DType(param.typeref.type), DEscapeName(param.name)));
    }
    f.writeln(");");
}

void DDecl(File* f, Decl decl, bool omitEnumPrefix)
{
    castSwitch!( //
            (Typedef decl) => DTypedefDecl(f, decl), //
            (Enum decl) => DEnumDecl(f,
                decl, omitEnumPrefix), //
            (Struct decl) => DStructDecl(f, decl), //
            (Function decl) => DFucntionDecl(f, decl, "", false) //
            )(decl);
}

static string[string] macroMap;

shared static this()
{
    // avoid c style cast
    macroMap = [
        "D3D_COMPILE_STANDARD_FILE_INCLUDE": "enum D3D_COMPILE_STANDARD_FILE_INCLUDE = cast(void*)1;",
        "ImDrawCallback_ResetRenderState": "enum ImDrawCallback_ResetRenderState = cast( ImDrawCallback ) ( - 1 );",
        "LUA_VERSION": "enum LUA_VERSION = \"Lua \" ~ LUA_VERSION_MAJOR ~ \".\" ~ LUA_VERSION_MINOR;",
        "LUA_REGISTRYINDEX": "enum LUA_REGISTRYINDEX = ( - 1000000 - 1000 );",
        "LUAL_NUMSIZES": "enum LUAL_NUMSIZES = ( ( lua_Integer ).sizeof  * 16 + ( lua_Number ).sizeof  );",
        "LUA_VERSUFFIX": "enum LUA_VERSUFFIX = \"_\" ~ LUA_VERSION_MAJOR ~ \"_\" ~ LUA_VERSION_MINOR;",
    ];
}

void dlangExport(Source[string] sourceMap, string dir, bool omitEnumPrefix)
{
    // clear dir
    if (exists(dir))
    {
        logf("rmdir %s", dir);
        rmdirRecurse(dir);
    }

    // write each source
    // auto sourcemap = makeView(m_sourceMap);
    auto hasComInterface = false;
    foreach (k, source; sourceMap)
    {
        // source.writeTo(dir);
        if (source.empty)
        {
            continue;
        }

        auto packageName = dir.baseName.stripExtension;

        // open
        auto path = format("%s/%s.d", dir, source.getName());
        // writeln(stem);
        logf("writeTo: %s(%d)", path, source.m_types.length);
        mkdirRecurse(dir);

        {
            auto f = File(path, "w");
            f.writeln(HEADLINE);
            f.writefln("module %s.%s;", packageName, source.getName());

            // imports
            string[] modules;
            foreach (src; source.m_imports)
            {
                if (!src.empty)
                {
                    f.writefln("import %s.%s;", packageName, src.getName());
                }

                foreach (m; src.m_modules)
                {
                    if (modules.find(m).empty)
                    {
                        f.writefln("import %s;", m);
                        modules ~= m;

                        if (m == moduleName!(core.sys.windows.unknwn))
                        {
                            f.writefln("import %s.guidutil;", packageName);
                            hasComInterface = true;
                        }
                    }
                }
            }

            // const
            foreach (macroDefinition; source.m_macros)
            {
                if (macroDefinition.tokens[0][0].isAlpha)
                {
                    // typedef ?
                    // IID_ID3DBlob = IID_ID3D10Blob;
                    // INTERFACE = ID3DInclude;
                    continue;
                }

                auto p = macroDefinition.name in macroMap;
                if (p)
                {
                    f.writeln(*p);
                }
                else
                {
                    f.writefln("enum %s = %s;", macroDefinition.name,
                            macroDefinition.tokens.join(" "));
                }
            }

            // types
            foreach (decl; source.m_types)
            {
                DDecl(&f, decl, omitEnumPrefix);
            }
        }
    }

    if (hasComInterface)
    {
        // write utility
        auto packageName = dir.baseName.stripExtension;
        auto path = format("%s/guidutil.d", dir);
        auto f = File(path, "w");
        f.writefln("module %s.guidutil;", packageName);
        f.writeln("
import std.uuid;
import core.sys.windows.basetyps;

GUID parseGUID(string guid)
{
    return toGUID(parseUUID(guid));
}
GUID toGUID(immutable std.uuid.UUID uuid)
{
    ubyte[8] data=uuid.data[8..$];
    return GUID(
                uuid.data[0] << 24
                |uuid.data[1] << 16
                |uuid.data[2] << 8
                |uuid.data[3],

                uuid.data[4] << 8
                |uuid.data[5],

                uuid.data[6] << 8
                |uuid.data[7],

                data
                );
}
");
    }

    // write package.d
    {
        auto packageName = dir.baseName.stripExtension;
        auto path = format("%s/package.d", dir);
        auto f = File(path, "w");
        f.writefln("module %s;", packageName);
        foreach (k, source; sourceMap)
        {
            if (source.empty())
            {
                continue;
            }
            f.writefln("public import %s.%s;", packageName, source.getName());
        }
    }
}
