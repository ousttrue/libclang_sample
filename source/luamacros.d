module luamacros;
import lua;

/*
** {==============================================================
** some useful macros
** ===============================================================
*/

// #define lua_getextraspace(L)	((void *)((char *)(L) - LUA_EXTRASPACE))

// #define lua_tonumber(L,i)	lua_tonumberx(L,(i),NULL)
// #define lua_tointeger(L,i)	lua_tointegerx(L,(i),NULL)

void lua_pop(lua_State* L, int n)
{
    lua_settop(L, -(n) - 1);
}

// #define lua_newtable(L)		lua_createtable(L, 0, 0)

// #define lua_register(L,n,f) (lua_pushcfunction(L, (f)), lua_setglobal(L, (n)))

// #define lua_pushcfunction(L,f)	lua_pushcclosure(L, (f), 0)

// #define lua_isfunction(L,n)	(lua_type(L, (n)) == LUA_TFUNCTION)
// #define lua_istable(L,n)	(lua_type(L, (n)) == LUA_TTABLE)
// #define lua_islightuserdata(L,n)	(lua_type(L, (n)) == LUA_TLIGHTUSERDATA)
// #define lua_isnil(L,n)		(lua_type(L, (n)) == LUA_TNIL)
// #define lua_isboolean(L,n)	(lua_type(L, (n)) == LUA_TBOOLEAN)
// #define lua_isthread(L,n)	(lua_type(L, (n)) == LUA_TTHREAD)
// #define lua_isnone(L,n)		(lua_type(L, (n)) == LUA_TNONE)
// #define lua_isnoneornil(L, n)	(lua_type(L, (n)) <= 0)

// #define lua_pushliteral(L, s)	lua_pushstring(L, "" s)

// #define lua_pushglobaltable(L)  \
// 	((void)lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_GLOBALS))

// #define lua_tostring(L,i)	lua_tolstring(L, (i), NULL)

// #define lua_insert(L,idx)	lua_rotate(L, (idx), 1)

// #define lua_remove(L,idx)	(lua_rotate(L, (idx), -1), lua_pop(L, 1))

// #define lua_replace(L,idx)	(lua_copy(L, -1, (idx)), lua_pop(L, 1))
