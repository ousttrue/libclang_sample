HEADLINE = "// This source code was generated by regenerator"

local DESCAPE_SYMBOLS = {module = true, ref = true, ["in"] = true}

function DEscapeName(src)
    if DESCAPE_SYMBOLS[src] then
        return "_" .. src
    end
    return src
end

-- avoid c style cast
DMACRO_MAP = {
    D3D_COMPILE_STANDARD_FILE_INCLUDE = "enum D3D_COMPILE_STANDARD_FILE_INCLUDE = cast(void*)1;",
    ImDrawCallback_ResetRenderState = "enum ImDrawCallback_ResetRenderState = cast( ImDrawCallback ) ( - 1 );",
    LUA_VERSION = 'enum LUA_VERSION = "Lua " ~ LUA_VERSION_MAJOR ~ "." ~ LUA_VERSION_MINOR;',
    LUA_REGISTRYINDEX = "enum LUA_REGISTRYINDEX = ( - 1000000 - 1000 );",
    LUAL_NUMSIZES = "enum LUAL_NUMSIZES = ( ( lua_Integer ).sizeof  * 16 + ( lua_Number ).sizeof  );",
    LUA_VERSUFFIX = 'enum LUA_VERSUFFIX = "_" ~ LUA_VERSION_MAJOR ~ "_" ~ LUA_VERSION_MINOR;'
}

DTYPE_MAP = {
    Void = "void",
    Bool = "bool",
    Int8 = "char",
    Int16 = "short",
    Int32 = "int",
    Int64 = "long",
    UInt8 = "ubyte",
    UInt16 = "ushort",
    UInt32 = "uint",
    UInt64 = "ulong",
    Float = "float",
    Double = "double"
}

function isInterface(decl)
    decl = decl.typedefSource

    if decl.class ~= "Struct" then
        return false
    end

    if decl.definition then
        -- resolve forward decl
        decl = decl.definition
    end

    return decl.isInterface
end

function DPointer(p)
    if p.ref.type.name == "ID3DInclude" then
        return "void*   "
    elseif isInterface(p.ref.type) then
        return string.format("%s", DType(p.ref.type))
    else
        return string.format("%s*", DType(p.ref.type))
    end
end

function DArray(a)
    return string.format("%s[%d]", DType(a.ref.type), a.size)
end

function DType(t)
    local name = DTYPE_MAP[t.class]
    if name then
        return name
    end
    if t.class == "Pointer" then
        return DPointer(t)
    elseif t.class == "Array" then
        return DArray(t)
    else
        return t.name
    end
end

function DTypedefDecl(f, t)
    -- print(t, t.ref)
    local dst = DType(t.ref.type)
    if dst then
        if t.name == dst then
            -- f.writefln("// samename: %s", t.m_name);
            return
        end

        writefln(f, "alias %s = %s;", t.name, dst)
        return
    end

    -- nameless
    writeln(f, "// typedef target nameless")
end

function DEnumDecl(f, decl, omitEnumPrefix)
    if not decl.name then
        writeln(f, "// enum nameless")
        return
    end

    writef(f, "enum %s", decl.name)
    f.writeln()

    if omitEnumPrefix then
        omit(decl)
    end

    writeln(f, "{")
    for i, value in ipairs(decl.values) do
        writefln(f, "    %s = 0x%x,", value.name, value.value)
    end
    writeln(f, "}")
end

SKIP_METHODS = {QueryInterface = true, AddRef = true, Release = true}

function DStructDecl(f, decl, typedefName)
    -- assert(!decl.m_forwardDecl);
    local name = typedefName or decl.name
    if not name then
        writeln(f, "// struct nameless")
        return
    end

    if decl.isInterface then
        -- com interface
        if decl.isForwardDecl then
            return
        end

        -- interface
        writef(f, "interface %s", name)
        if decl.base then
            writef(f, ": %s", decl.base.name)
        end

        writeln(f)
        writeln(f, "{")
        if not decl.iid.empty then
            writefln(f, '    static const iidof = parseGUID("%s");', decl.iid.toString())
        end

        -- methods
        for i, method in ipairs(decl.methods) do
            if SKIP_METHODS[method.name] then
                writefln(f, "    // skip %s", method.name)
            else
                DFunctionDecl(f, method, "    ", true)
            end
        end
        writeln(f, "}")
    else
        if decl.isForwardDecl then
            -- forward decl
            if #decl.fields > 0 then
                error("forward decl has fields")
            end
            writefln(f, "struct %s;", name)
        else
            writefln(f, "struct %s", name)
            writeln(f, "{")
            for i, field in ipairs(decl.fields) do
                local typeName = DType(field.type)
                if not typeName then
                    local fieldType = field.type
                    if fieldType.class == "Struct" then
                        if fieldType.isUnion then
                            writefln(f, "    union {")
                            for i, unionField in ipairs(structDecl.fields) do
                                local unionFieldTypeName = DType(unionField.type)
                                writefln(f, "        %s %s;", unionFieldTypeName, DEscapeName(unionField.name))
                            end
                            writefln(f, "    }")
                        else
                            writefln(f, "   // anonymous struct %s;", DEscapeName(field.name))
                        end
                    else
                        error("unknown")
                    end
                else
                    writefln(f, "    %s %s;", typeName, DEscapeName(field.name))
                end
            end

            writeln(f, "}")
        end
    end
end

function DFunctionDecl(f, decl, indent, isMethod)
    indent = indent or ""
    if (not isMethod) and (not decl.dllExport) then
        -- filtering functions
        -- target library(d3d11.h, libclang.h, lua.h) specific...

        -- for D3D11CreateDevice ... etc
        local retType = decl.ret
        -- if (!retType)
        -- {
        --     return;
        -- }
        if retType.name ~= "HRESULT" then
            return
        end
    -- debug auto isCom = true;
    end

    f:write(indent)
    if decl.isExternC then
        f:write("extern(C) ")
    end

    f:write(DType(decl.ret))
    f:write(" ")
    f:write(decl.name)
    f:write("(")

    local isFirst = true
    for i, param in ipairs(decl.params) do
        if isFirst then
            isFirst = false
        else
            f:write(", ")
        end

        if param.ref.hasConstRecursive then
            f:write("const ")
        end

        f:write(string.format("%s %s", DType(param.ref.type), DEscapeName(param.name)))
    end
    writeln(f, ");")
end

function DDecl(f, decl, omitEnumPrefix)
    if decl.class == "Typedef" then
        DTypedefDecl(f, decl)
    elseif decl.class == "Enum" then
        DEnumDecl(f, decl)
    elseif decl.class == "Struct" then
        DStructDecl(f, decl)
    elseif decl.class == "Function" then
        DFunctionDecl(f, decl)
    else
        error("unknown", decl)
    end
end

function DImport(f, packageName, src, modules)
    if not src.empty then
        -- inner package
        writefln(f, "import %s.%s;", packageName, src.name)
    end

    for j, m in ipairs(src.modules) do
        -- core.sys.windows.windef etc...
        if not modules[m] then
            modules[m] = true
            writefln(f, "import %s;", m)
        end
    end
end

function DConst(f, macroDefinition)
    if not isFirstAlpha(macroDefinition.tokens[1]) then
        local p = DMACRO_MAP[macroDefinition.name]
        if p then
            writeln(f, p)
        else
            writefln(f, "enum %s = %s;", macroDefinition.name, table.concat(macroDefinition.tokens, " "))
        end
    end
end

function DSource(f, packageName, source)
    writeln(f, HEADLINE)
    writefln(f, "module %s.%s;", packageName, source.name)

    -- imports
    local modules = {}
    for i, src in ipairs(source.imports) do
        DImport(f, packageName, src, modules)
    end

    -- const
    for j, macroDefinition in ipairs(source.macros) do
        DConst(f, macroDefinition)
    end

    -- types
    for j, decl in ipairs(source.types) do
        DDecl(f, decl, omitEnumPrefix)
    end
end

function DPackage(f, packageName, sourceMap)
    writeln(f, HEADLINE)
    writefln(f, "module %s;", packageName)
    local keys = {}
    for k, source in pairs(sourceMap) do
        table.insert(keys, k)
    end
    table.sort(keys)
    for i, k in ipairs(keys) do
        local source = sourceMap[k]
        if not source.empty then
            writefln(f, "public import %s.%s;", packageName, source.name)
        end
    end
end

return {
    Decl = DDecl,
    Import = DImport,
    Const = DConst,
    Package = DPackage,
    Source = DSource,
}
